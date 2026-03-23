#!/usr/bin/env bash
# Runs every shell test file under bootstrap/tests and prints per-file
# results plus a final passed/failed/total summary.
set -u

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$BOOTSTRAP_DIR/tests"

PASSED=0
FAILED=0
TOTAL=0
FOUND_ANY=0

echo "Running tests from: $TEST_DIR"

for test in "$TEST_DIR"/*.sh; do
  if [[ ! -f "$test" ]]; then
    continue
  fi

  FOUND_ANY=1
  TOTAL=$((TOTAL + 1))
  echo "----------------------------------"
  echo "Running: $(basename "$test")"

  if ! bash "$test"; then
    echo "❌ Failed: $(basename "$test")"
    FAILED=$((FAILED + 1))
  else
    echo "✅ Passed: $(basename "$test")"
    PASSED=$((PASSED + 1))
  fi
done

echo "----------------------------------"

if [[ "$FOUND_ANY" -eq 0 ]]; then
  echo "No test files found in $TEST_DIR"
  exit 1
fi

echo "Files: $PASSED passed, $FAILED failed, $TOTAL total"

if [[ "$FAILED" -ne 0 ]]; then
  echo "❌ Some tests failed"
  exit 1
fi

echo "✅ All tests passed"
