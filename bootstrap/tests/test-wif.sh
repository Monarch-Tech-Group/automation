#!/usr/bin/env bash
# Tests Workload Identity Federation bootstrap helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/google-cloud/wif.sh"

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

test_wif_configuration_uses_repository_defaults() {
  REPO_NAME="survey-app"
  PROJECT_NUMBER="123456789"
  GITHUB_REPO_FULL="acme/survey-app"
  DEPLOYER_SA_EMAIL="github-deployer@demo-project.iam.gserviceaccount.com"
  unset WIF_POOL_ID WIF_PROVIDER_ID WIF_PROVIDER_RESOURCE || true

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"
    printf '%s' "$default"
  }

  ensure_wif_pool() { return 0; }
  ensure_wif_provider() { return 0; }
  ensure_wif_service_account_binding() { return 0; }

  configure_wif

  assert_equals "github-pool" "$WIF_POOL_ID" \
    "WIF configuration defaults the pool identifier"
  assert_equals "survey-app-provider" "$WIF_PROVIDER_ID" \
    "WIF configuration defaults the provider identifier from the repository name"
  assert_equals "projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/survey-app-provider" "$WIF_PROVIDER_RESOURCE" \
    "WIF configuration records the provider resource path for GitHub secrets"
}

test_wif_provider_creation_is_skipped_when_the_provider_exists() {
  local invoked=0

  WIF_POOL_ID="github"
  WIF_PROVIDER_ID="survey-app"

  wif_provider_exists() {
    return 0
  }

  gcloud() {
    invoked=1
  }

  ensure_wif_provider

  assert_equals "0" "$invoked" \
    "WIF provider creation is skipped when the provider already exists"
}

test_wif_service_account_binding_grants_oidc_principals_impersonation_and_token_creation() {
  local binding_calls=0
  local recorded_roles=""

  source "$BOOTSTRAP_ROOT/scripts/google-cloud/wif.sh"

  PROJECT_NUMBER="123456789"
  WIF_POOL_ID="github-pool"
  GITHUB_REPO_FULL="acme/survey-app"
  DEPLOYER_SA_EMAIL="github-deployer@demo-project.iam.gserviceaccount.com"

  gcloud() {
    binding_calls=$((binding_calls + 1))
    recorded_roles="${recorded_roles}|$*"
  }

  ensure_wif_service_account_binding

  assert_equals "2" "$binding_calls" \
    "WIF service account binding grants both impersonation and access-token creation"

  case "$recorded_roles" in
    *"roles/iam.workloadIdentityUser"* ) ;;
    * )
      fail "WIF service account binding should grant workload identity user"
      ;;
  esac

  case "$recorded_roles" in
    *"roles/iam.serviceAccountTokenCreator"* ) ;;
    * )
      fail "WIF service account binding should grant service account token creator"
      ;;
  esac

  pass "WIF service account binding grants OIDC principals impersonation and token creation"
}

run_test test_wif_configuration_uses_repository_defaults
run_test test_wif_provider_creation_is_skipped_when_the_provider_exists
run_test test_wif_service_account_binding_grants_oidc_principals_impersonation_and_token_creation
