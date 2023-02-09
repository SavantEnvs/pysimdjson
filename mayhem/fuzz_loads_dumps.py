#!/usr/bin/env python3

import atheris
import sys

import fuzz_helpers

with atheris.instrument_imports():
    import simdjson


def TestOneInput(data):
    fdp = fuzz_helpers.EnhancedFuzzedDataProvider(data)
    try:
        original_str = fdp.ConsumeRemainingString()
        if fdp.ConsumeBool():
            parser = simdjson.Parser()
            json = parser.parse(original_str)
        else:
            json = simdjson.loads(original_str)
            dumped = simdjson.dumps(json)

    except ValueError as e:
        if 'JSON' in str(e):
            return -1


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
