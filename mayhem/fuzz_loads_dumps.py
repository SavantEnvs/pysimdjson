#!/usr/bin/env python3
#
# Atheris harness for TkTech/pysimdjson. Drives the SAME public API surface the library exposes:
# Parser.parse, simdjson.loads, simdjson.dumps — the hot path being the csimdjson native
# extension (Cython + vendored simdjson C++ parser).
#
# For native-extension coverage the csimdjson .so is built with
# -fsanitize=fuzzer-no-link (SanitizerCoverage). Its sancov references
# resolve against Atheris' ubsan_with_fuzzer.so, LD_PRELOADed by the /mayhem/fuzz-api launcher
# (see mayhem/launcher.c) — Atheris' documented native-extension mode.
import sys

import atheris

import fuzz_helpers

with atheris.instrument_imports():
    import simdjson


def TestOneInput(data):
    fdp = fuzz_helpers.EnhancedFuzzedDataProvider(data)
    try:
        original_str = fdp.ConsumeRemainingString()
        if fdp.ConsumeBool():
            parser = simdjson.Parser()
            parser.parse(original_str)
        else:
            json = simdjson.loads(original_str)
            simdjson.dumps(json)
    except ValueError as e:
        if 'JSON' in str(e):
            return -1


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
