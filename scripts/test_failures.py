#!/usr/bin/env python3
"""Prints each failing test and its message from an xcresult summary (JSON on stdin).

xcodebuild's -quiet output lists failing test names but not why they failed; this fills that gap
and turns each failure into a GitHub annotation. With --require-no-skips it also fails when any
test was skipped or failed, for suites that must really run on the chosen simulator.
"""
import json
import sys

try:
    summary = json.load(sys.stdin)
except ValueError as error:
    print(f"No test summary to read ({error}).")
    sys.exit(0)

failures = summary.get("testFailures", [])
print(f"{summary.get('result', '?')}: {summary.get('failedTests', len(failures))} failed, "
      f"{summary.get('passedTests', '?')} passed, {summary.get('skippedTests', '?')} skipped")
for failure in failures:
    name = f"{failure.get('targetName', '')} › {failure.get('testName', '?')}"
    text = (failure.get("failureText") or "").strip()
    print(f"\n{name}\n    " + text.replace("\n", "\n    "))
    print(f"::error title={name}::{text.replace(chr(10), ' ')}")

if "--require-no-skips" in sys.argv[1:]:
    skipped = summary.get("skippedTests", 0)
    if skipped or failures:
        print(f"::error::{skipped} skipped and {len(failures)} failed; every test in this suite must run and pass")
        sys.exit(1)
