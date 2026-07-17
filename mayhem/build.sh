#!/usr/bin/env bash
#
# pysimdjson/mayhem/build.sh — build the Atheris fuzz target for TkTech/pysimdjson.
#
# This is a PYTHON (Atheris/libFuzzer) project whose hot path is a Cython/C++ native extension
# (csimdjson, wrapping the vendored simdjson amalgamation). The "build" is:
#   1) install the build backend + test deps + atheris, OFFLINE, from the wheelhouse the Dockerfile
#      baked into /opt/toolchains/python/wheelhouse (air-gapped, re-runnable — SPEC §6.5);
#   2) compile + install the csimdjson extension with SanitizerCoverage
#      (-fsanitize=fuzzer-no-link) so the C++ parser itself feeds libFuzzer/Atheris edge coverage
#      (the harness re-exports Atheris' embedded libFuzzer symbols via RTLD_GLOBAL before importing
#      csimdjson, resolving the extension's __sanitizer_cov_* references);
#   3) compile tiny ELF launchers (launcher.c) so the Mayhem target `cmd` is a native executable
#      (Mayhem rejects script targets; fuzz-smoke checks the ELF magic). Each launcher exec's
#      `python3 <script> "$@"`, forwarding libFuzzer flags to Atheris:
#        - /mayhem/fuzz-api             : the Mayhem libFuzzer target (Atheris iterates).
#        - /mayhem/fuzz-api-standalone  : run-once reproducer (Atheris replays one file arg).
#        - /mayhem/run-tests            : the oracle runner mayhem/test.sh drives (pytest).
#
# NOTE on sanitizers: ASan inside an embedded CPython is not viable without preloading the ASan
# runtime into the interpreter (it breaks every python3 invocation in the image), so the extension
# is built with SanitizerCoverage only ($SANITIZER_FLAGS is not applied to python extension code).
# We still thread $DEBUG_FLAGS into every native compile so the spec's debug-info contract
# (DWARF < 4) holds on every emitted object.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) so an explicit empty --build-arg SANITIZER_FLAGS= builds without sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS: explicit DWARF-3 so Mayhem triage can read symbols (clang-19's plain -g emits DWARF-5).
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}"
: "${CXX:=clang++}"
: "${SRC:=/mayhem}"
: "${WHEELHOUSE:=/opt/toolchains/python/wheelhouse}"
# atheris + csimdjson install here (pip --user), NOT under $HOME (SPEC §6.2 item 8).
: "${PYTHONUSERBASE:=/opt/toolchains/python/userbase}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX SRC WHEELHOUSE PYTHONUSERBASE
OUT=/mayhem

cd "$SRC"

# ── 1) Python deps — OFFLINE from the baked wheelhouse (idempotent; "already satisfied" on re-run) ──
PIP="python3 -m pip install --user --break-system-packages"
if [ -d "$WHEELHOUSE" ]; then
  PIP="$PIP --no-index --find-links $WHEELHOUSE"
fi
$PIP atheris 'setuptools>=74.1' Cython wheel pytest pytest-benchmark numpy orjson

# ── 2) Build + install the csimdjson native extension, instrumented for edge coverage ───────────
# -fsanitize=fuzzer-no-link instruments the C++ parser with SanitizerCoverage (edge coverage)
# without linking a libFuzzer main. The sancov symbols resolve at runtime against Atheris'
# ubsan_with_fuzzer.so, which the launcher LD_PRELOADs (see launcher.c). This is the exact
# sanitizer configuration of this repo's historical Mayhem runs (595–1077 edges); an ASan-built
# extension records 0 edges on the Mayhem side. DWARF-3 per the debug-info contract.
# SIMDJSON_IMPLEMENTATION_FALLBACK=1 matches upstream's cibuildwheel environment (portable across
# host microarchitectures).
EXT_SAN="-fsanitize=fuzzer-no-link -fno-omit-frame-pointer"
export CFLAGS="${CFLAGS:-} $EXT_SAN $DEBUG_FLAGS -O2"
export CXXFLAGS="${CXXFLAGS:-} $EXT_SAN $DEBUG_FLAGS -O2"
export CPPFLAGS="${CPPFLAGS:-} -DSIMDJSON_IMPLEMENTATION_FALLBACK=1"
$PIP --no-build-isolation --force-reinstall --no-deps .

# Resolve Atheris' ubsan_with_fuzzer.so (bundles libFuzzer + UBSan runtime + sancov) — the runtime
# the instrumented extension and the fuzzing engine both need. Baked into the launchers at compile
# time.
PRELOAD="$(python3 -c 'import os, atheris; print(os.path.join(os.path.dirname(os.path.dirname(atheris.__file__)), "ubsan_with_fuzzer.so"))')"
[ -f "$PRELOAD" ] || { echo "FATAL: atheris ubsan_with_fuzzer.so not found at $PRELOAD" >&2; exit 1; }
echo "atheris preload: $PRELOAD"

# Sanity: the harnessed module must import + parse under the libFuzzer preload.
LD_PRELOAD="$PRELOAD" python3 -c '
import simdjson
assert simdjson.loads("[1,2,3]") == [1, 2, 3]
assert simdjson.loads(simdjson.dumps({"a": 1})) == {"a": 1}
' || { echo "FATAL: simdjson failed to import/parse" >&2; exit 1; }

# ── 3) Native ELF launchers ─────────────────────────────────────────────────────────────────────
# Sanitizing a ~30-line exec shim is pointless, so the launcher is built WITHOUT $SANITIZER_FLAGS
# but WITH $DEBUG_FLAGS (DWARF-3) to satisfy the debug-info contract. The fuzzed code is
# instrumented by Atheris (python) + SanitizerCoverage (C++ extension). Each launcher bakes in
# the atheris preload so the instrumented extension resolves its runtime.
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/fuzz_loads_dumps.py\"" \
    -DPRELOAD_PATH="\"$PRELOAD\"" \
    -DUSERBASE_PATH="\"$PYTHONUSERBASE\"" \
    -o "$OUT/fuzz-api" "$SRC/mayhem/launcher.c"

# Standalone run-once reproducer: same binary (Atheris replays a single file argument).
cp -f "$OUT/fuzz-api" "$OUT/fuzz-api-standalone"

# Test-suite runner for the oracle: exec's pytest over the project's own tests. Because it lives at
# a NON-system path, the anti-reward-hack neuter (LD_PRELOAD _exit(0) on non-system exes) trips it,
# making mayhem/test.sh a genuinely behavioral oracle.
"$CC" $DEBUG_FLAGS -O1 \
    -DHARNESS_PATH="\"$SRC/mayhem/run_tests.py\"" \
    -DPRELOAD_PATH="\"$PRELOAD\"" \
    -DUSERBASE_PATH="\"$PYTHONUSERBASE\"" \
    -o "$OUT/run-tests" "$SRC/mayhem/launcher.c"

echo "build.sh complete:"
ls -la "$OUT/fuzz-api" "$OUT/fuzz-api-standalone" "$OUT/run-tests"
