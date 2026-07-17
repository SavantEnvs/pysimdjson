#!/usr/bin/env python3
#
# run_tests.py — oracle driver for pysimdjson: runs the project's OWN pytest suite (tests/) and
# prints a machine-readable summary line that mayhem/test.sh parses into CTRF counts.
# Driven via the /mayhem/run-tests ELF launcher so the anti-reward-hack neuter trips it.
import os
import sys

os.chdir(os.environ.get("SRC", "/mayhem"))

import pytest


class _Summary:
    def __init__(self):
        self.counts = {"passed": 0, "failed": 0, "skipped": 0, "error": 0}

    def pytest_runtest_logreport(self, report):
        if report.when == "call" or (report.when == "setup" and report.outcome != "passed"):
            if report.outcome == "passed" and report.when == "call":
                self.counts["passed"] += 1
            elif report.outcome == "failed":
                self.counts["failed"] += 1
            elif report.outcome == "skipped":
                self.counts["skipped"] += 1


def main():
    summary = _Summary()
    rc = pytest.main(
        ["-p", "no:cacheprovider", "-v", "--runslow", "tests/"] + sys.argv[1:],
        plugins=[summary],
    )
    c = summary.counts
    print(
        "PYTEST_SUMMARY passed=%d failed=%d skipped=%d rc=%d"
        % (c["passed"], c["failed"], c["skipped"], rc)
    )
    sys.exit(0 if rc == 0 else 1)


if __name__ == "__main__":
    main()
