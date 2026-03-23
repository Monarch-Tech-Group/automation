#!/usr/bin/env bash
# Tests GitHub output and summary helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/output.sh"

pass() {
  printf "✅ %s\n" "$1"
}

fail() {
  printf "❌ %s\n" "$1" >&2
  exit 1
}

run_test() {
  local test_name="$1"
  printf "Running test: %s\n" "$test_name"
  "$test_name"
}

test_summary_includes_the_workflow_run_when_present() {
  local output

  GITHUB_REPO_FULL="acme/demo"
  PROJECT_ID="demo-project"
  REGION="us-central1"
  CLIENT_TARGET_SERVICE_NAME="demo-app"
  CLIENT_WORKFLOW_RUN_URL="https://github.com/acme/demo/actions/runs/1234"

  output="$(print_summary)"

  case "$output" in
    *"Client deploy target: demo-app"* ) ;;
    * )
      fail "summary output should include the client deploy target when a client deployment exists"
      ;;
  esac

  case "$output" in
    *"Client workflow URL: https://github.com/acme/demo/actions/runs/1234"* ) ;;
    * )
      fail "summary output should include the client workflow run URL when a client run exists"
      ;;
  esac

  pass "summary output includes client deployment details when they are available"
}

test_summary_omits_the_workflow_run_when_bootstrap_has_not_dispatched_yet() {
  local output

  GITHUB_REPO_FULL="acme/demo"
  PROJECT_ID="demo-project"
  REGION="us-central1"
  unset CLIENT_TARGET_SERVICE_NAME CLIENT_WORKFLOW_RUN_URL SERVICE_TARGET_SERVICE_NAME SERVICE_WORKFLOW_RUN_URL SERVICE_API_BASE_URL || true

  output="$(print_summary)"

  case "$output" in
    *"Client workflow URL:"*|*"Service workflow URL:"* )
      fail "summary output should omit workflow details before dispatch"
      ;;
    * )
      ;;
  esac

  pass "summary output omits deployment workflow details before dispatch"
}

run_test test_summary_includes_the_workflow_run_when_present
run_test test_summary_omits_the_workflow_run_when_bootstrap_has_not_dispatched_yet
