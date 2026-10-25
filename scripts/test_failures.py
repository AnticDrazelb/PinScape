#!/usr/bin/env python3
"""Prints each failing test and its message from an xcresult summary (JSON on stdin).

xcodebuild's -quiet output lists failing test names but not why they failed; this fills that gap
and turns each failure into a GitHub annotation.
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
