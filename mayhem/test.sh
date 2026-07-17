#!/usr/bin/env bash
#
# pysimdjson/mayhem/test.sh — behavioral oracle for TkTech/pysimdjson.
#
# It RUNS the project's OWN pytest suite (tests/ — the full upstream unit + JSONTestSuite
# minefield tests, exercising the SAME csimdjson parse/dump pipeline the fuzzer drives) via the
# /mayhem/run-tests launcher built by mayhem/build.sh, and converts the pytest counts into CTRF.
# It never builds; build.sh already installed the package + test deps.
#
# Anti-reward-hack note: run-tests lives at /mayhem (a NON-system path), so the verify-repo
# sabotage neuter (_exit(0) on non-system exes) trips it -> no PYTEST_SUMMARY line -> FAIL.
# The suite itself asserts parsed values (known-answer tests), so a neutered/no-op parser fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

RUNNER="$SRC/run-tests"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if [ ! -x "$RUNNER" ]; then
  echo "missing $RUNNER — run mayhem/build.sh first" >&2
  emit_ctrf "pytest" 0 1 0; exit 2
fi

echo "=== running the upstream pytest suite (tests/) ==="
OUT="$("$RUNNER" 2>&1)"; RC=$?
echo "$OUT"

SUMMARY="$(grep -m1 '^PYTEST_SUMMARY ' <<<"$OUT" || true)"
if [ -z "$SUMMARY" ]; then
  echo "no PYTEST_SUMMARY from the runner (neutered or crashed, rc=$RC)" >&2
  emit_ctrf "pytest" 0 1 0; exit 1
fi

PASSED="$(sed -n 's/.*passed=\([0-9]*\).*/\1/p' <<<"$SUMMARY")"
FAILED="$(sed -n 's/.*failed=\([0-9]*\).*/\1/p' <<<"$SUMMARY")"
SKIPPED="$(sed -n 's/.*skipped=\([0-9]*\).*/\1/p' <<<"$SUMMARY")"

# A pytest run that collected nothing (or lost tests) is a failure, not a pass.
if [ "${PASSED:-0}" -lt 1 ]; then
  echo "pytest reported no passing tests — suite did not run" >&2
  emit_ctrf "pytest" "${PASSED:-0}" 1 "${SKIPPED:-0}"; exit 1
fi

emit_ctrf "pytest" "$PASSED" "$FAILED" "$SKIPPED"
