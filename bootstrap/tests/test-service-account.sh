#!/usr/bin/env bash
# Tests Google Cloud service account and IAM bootstrap helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/google-cloud/service-account.sh"

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

test_service_account_creation_is_skipped_when_the_account_exists() {
  local created=0

  PROJECT_ID="demo-project"

  service_account_exists() {
    return 0
  }

  gcloud() {
    created=1
  }

  ensure_service_account "github-deployer" "GitHub deployer"

  assert_equals "0" "$created" \
    "service account creation is skipped when the account already exists"
}

test_service_account_creation_waits_until_the_account_is_visible_in_iam() {
  local created=0
  local describe_attempts=0

  PROJECT_ID="demo-project"

  service_account_exists() {
    describe_attempts=$((describe_attempts + 1))
    [[ "$describe_attempts" -ge 2 ]]
  }

  gcloud() {
    if [[ "$1" == "iam" && "$2" == "service-accounts" && "$3" == "create" ]]; then
      created=1
      return 0
    fi

    return 1
  }

  sleep() {
    return 0
  }

  ensure_service_account "github-deployer" "GitHub deployer"

  assert_equals "1" "$created" \
    "service account creation issues the create command when the account is missing"
  assert_equals "2" "$describe_attempts" \
    "service account creation waits until the new account is visible in IAM before continuing"
}

test_iam_configuration_grants_deployer_and_runtime_access() {
  local project_bindings=0
  local service_bindings=0

  DEPLOYER_SA_ID="github-deployer"
  RUNTIME_SA_ID="cloudrun-runtime"
  DEPLOYER_SA_EMAIL="github-deployer@demo-project.iam.gserviceaccount.com"
  RUNTIME_SA_EMAIL="cloudrun-runtime@demo-project.iam.gserviceaccount.com"

  ensure_service_account() {
    return 0
  }

  ensure_project_binding() {
    project_bindings=$((project_bindings + 1))
  }

  ensure_service_account_binding() {
    service_bindings=$((service_bindings + 1))
  }

  configure_iam_roles

  assert_equals "2" "$project_bindings" \
    "IAM configuration grants the deployer project-level access for Cloud Run and Artifact Registry"
  assert_equals "1" "$service_bindings" \
    "IAM configuration grants the deployer permission to impersonate the runtime service account"
}

run_test test_service_account_creation_is_skipped_when_the_account_exists
run_test test_service_account_creation_waits_until_the_account_is_visible_in_iam
run_test test_iam_configuration_grants_deployer_and_runtime_access
