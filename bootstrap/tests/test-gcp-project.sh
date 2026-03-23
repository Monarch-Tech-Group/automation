#!/usr/bin/env bash
# Tests Google Cloud project bootstrap helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/google-cloud/project.sh"

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

test_project_configuration_creates_a_missing_project_and_selects_it() {
  local created=""
  local selected=""

  REPO_NAME="survey-app"
  unset PROJECT_NAME PROJECT_ID PROJECT_NUMBER || true

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"
    printf '%s' "$default"
  }

  gcp_project_exists() {
    return 1
  }

  create_gcp_project() {
    created="$1|$2"
  }

  lookup_project_number() {
    printf '123456789'
  }

  gcloud() {
    if [[ "$1 $2" == "config set" ]]; then
      selected="$4"
    fi
  }

  configure_gcp_project

  assert_equals "survey-app|survey-app" "$created" \
    "project configuration creates a missing project using the derived identifiers"
  assert_equals "123456789" "$PROJECT_NUMBER" \
    "project configuration records the numeric project identifier"
  assert_equals "survey-app" "$selected" \
    "project configuration selects the target project in gcloud"
}

test_project_configuration_rejects_an_invalid_project_identifier() {
  local output

  PROJECT_NAME="Demo"
  PROJECT_ID="BadProject"

  output="$(
    (
      configure_gcp_project
    ) 2>&1
  )" || true

  case "$output" in
    *"Invalid project ID format: BadProject"* ) ;;
    * )
      fail "project configuration should reject an invalid project identifier"
      ;;
  esac

  pass "project configuration rejects an invalid project identifier"
}

run_test test_project_configuration_creates_a_missing_project_and_selects_it
run_test test_project_configuration_rejects_an_invalid_project_identifier
