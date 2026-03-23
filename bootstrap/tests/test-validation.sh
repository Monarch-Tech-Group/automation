#!/usr/bin/env bash
# Tests Google Cloud project identifier validation helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/google-cloud/validation.sh"

pass() {
  printf "✅ %s\n" "$1"
}

fail() {
  printf "❌ %s\n" "$1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$actual" == "$expected" ]]; then
    pass "$message"
  else
    fail "$message: expected '$expected' but got '$actual'"
  fi
}

run_test() {
  local test_name="$1"
  printf "Running test: %s\n" "$test_name"
  "$test_name"
}

test_project_identifier_sanitization_produces_a_gcloud_friendly_value() {
  local actual

  actual="$(sanitize_project_id "My Demo_App!")"

  assert_equals "my-demo-app" "$actual" \
    "project identifier sanitization produces a lowercase, hyphenated value"
}

test_project_identifier_validation_rejects_short_values() {
  if validate_project_id_format "abc"; then
    fail "project identifier validation should reject values that are too short"
  fi

  pass "project identifier validation rejects values that are too short"
}

run_test test_project_identifier_sanitization_produces_a_gcloud_friendly_value
run_test test_project_identifier_validation_rejects_short_values
