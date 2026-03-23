#!/usr/bin/env bash
# Tests workflow parsing and GitHub configuration writing for bootstrap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOOTSTRAP_ROOT/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/github-actions.sh"
source "$BOOTSTRAP_ROOT/scripts/output.sh"

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

test_deployment_target_defaults_to_the_client_workflow() {
  PROJECT_ID="demo-project"
  unset REPOSITORY_DEPLOYMENT_KIND DEPLOYMENT_TARGETS CLIENT_WORKFLOW_PATH CLIENT_SERVICE_DEFAULT_NAME || true

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"
    printf '%s' "$default"
  }

  configure_repository_deployment_plan
  configure_deployment_target client

  assert_equals "service" "$(REPOSITORY_DEPLOYMENT_KIND= ; prompt_default() { printf '%s' "$2"; }; configure_repository_deployment_plan >/dev/null 2>&1; printf '%s' "$REPOSITORY_DEPLOYMENT_KIND")" \
    "repository deployment plan defaults to the service shape"
  assert_equals ".github/workflows/client-deploy.yml" "$CLIENT_WORKFLOW_PATH" \
    "deployment target uses the client workflow"
  assert_equals "demo-project-client" "$CLIENT_SERVICE_DEFAULT_NAME" \
    "deployment target defaults the client service name from the project identifier"
}

test_repository_deployment_plan_accepts_the_client_shortcut() {
  REPOSITORY_DEPLOYMENT_KIND="c"
  unset DEPLOYMENT_TARGETS || true

  configure_repository_deployment_plan

  assert_equals "client" "$REPOSITORY_DEPLOYMENT_KIND" \
    "repository deployment plan accepts c as the client shortcut"
  assert_equals "client" "$DEPLOYMENT_TARGETS" \
    "repository deployment plan maps the client shortcut to the client target"
}

test_repository_deployment_plan_accepts_the_fullstack_shortcut() {
  REPOSITORY_DEPLOYMENT_KIND="b"
  unset DEPLOYMENT_TARGETS || true

  configure_repository_deployment_plan

  assert_equals "fullstack" "$REPOSITORY_DEPLOYMENT_KIND" \
    "repository deployment plan accepts b as the fullstack shortcut"
  assert_equals "service client" "$DEPLOYMENT_TARGETS" \
    "repository deployment plan maps the fullstack shortcut to the service-then-client target order"
}

test_deployment_target_switches_to_the_service_workflow() {
  PROJECT_ID="demo-project"
  REPOSITORY_DEPLOYMENT_KIND="s"
  unset CLIENT_WORKFLOW_PATH CLIENT_SERVICE_DEFAULT_NAME || true

  configure_repository_deployment_plan
  configure_deployment_target service

  assert_equals "service" "$DEPLOYMENT_TARGETS" \
    "repository deployment plan schedules only the service deployment for service repos"
  assert_equals ".github/workflows/service-deploy.yml" "$CLIENT_WORKFLOW_PATH" \
    "deployment target switches to the service workflow when the service kind is service"
  assert_equals "demo-project-service" "$CLIENT_SERVICE_DEFAULT_NAME" \
    "deployment target defaults the service name from the project identifier"
}

test_repository_deployment_plan_schedules_service_before_client_for_fullstack_repos() {
  REPOSITORY_DEPLOYMENT_KIND="fullstack"
  unset DEPLOYMENT_TARGETS || true

  configure_repository_deployment_plan

  assert_equals "service client" "$DEPLOYMENT_TARGETS" \
    "repository deployment plan schedules the service deployment before the client deployment for fullstack repos"
}

test_configure_client_workflow_contract_extracts_expected_values() {
  local original_workflow_path="${CLIENT_WORKFLOW_PATH:-}"

  CLIENT_WORKFLOW_PATH="$REPO_ROOT/.github/workflows/client-deploy.yml"
  configure_client_workflow_contract

  assert_equals "GCR_IMAGE_NAME" "$CLIENT_SERVICE_NAME_SECRET_NAME" \
    "configure_client_workflow_contract extracts service secret name"
  assert_equals "GCR_REGION" "$CLIENT_REGION_SECRET_NAME" \
    "configure_client_workflow_contract extracts region secret name"
  assert_equals "CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT" "$CLIENT_RUNTIME_SERVICE_ACCOUNT_SECRET_NAME" \
    "configure_client_workflow_contract extracts runtime service account secret name"
  assert_equals "GCR_CLIENT_REPOSITORY" "$CLIENT_REPOSITORY_SECRET_NAME" \
    "configure_client_workflow_contract extracts repository secret name"
  assert_equals "80" "$CLIENT_SERVICE_PORT" \
    "configure_client_workflow_contract extracts deploy port"
  assert_equals "VITE_API_BASE_URL" "${CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[*]}" \
    "configure_client_workflow_contract excludes GitHub-managed secrets from bootstrap prompts"

  CLIENT_WORKFLOW_PATH="$original_workflow_path"
}

test_configure_client_workflow_contract_requires_workflow_dispatch() {
  local tmp_workflow
  local original_workflow_path="${CLIENT_WORKFLOW_PATH:-}"

  tmp_workflow="$(mktemp)"
  sed '/workflow_dispatch:/d' "$REPO_ROOT/.github/workflows/client-deploy.yml" > "$tmp_workflow"
  CLIENT_WORKFLOW_PATH="$tmp_workflow"

  if ( configure_client_workflow_contract >/dev/null 2>&1 ); then
    rm -f "$tmp_workflow"
    fail "configure_client_workflow_contract should fail when workflow_dispatch is missing"
  else
    pass "configure_client_workflow_contract rejects workflows without workflow_dispatch"
  fi

  rm -f "$tmp_workflow"
  CLIENT_WORKFLOW_PATH="$original_workflow_path"
}

test_configure_service_workflow_contract_allows_optional_deploy_flags_to_be_missing() {
  local original_workflow_path="${CLIENT_WORKFLOW_PATH:-}"

  CLIENT_WORKFLOW_PATH="$REPO_ROOT/.github/workflows/service-deploy.yml"
  configure_client_workflow_contract

  assert_equals "" "$CLIENT_SERVICE_CPU" \
    "service workflow parsing tolerates a missing cpu flag"
  assert_equals "" "$CLIENT_SERVICE_MEMORY" \
    "service workflow parsing tolerates a missing memory flag"
  assert_equals "3001" "$CLIENT_SERVICE_PORT" \
    "service workflow parsing still extracts the required service port"

  CLIENT_WORKFLOW_PATH="$original_workflow_path"
}

test_collect_workflow_runtime_secrets_skips_cleanly_when_a_workflow_has_no_extra_runtime_secrets() {
  CLIENT_WORKFLOW_EXTRA_SECRET_NAMES=()
  unset WORKFLOW_SECRET_VALUE_VITE_API_BASE_URL || true

  prompt_required() {
    fail "collect_workflow_runtime_secrets should not prompt when no extra workflow secrets exist"
  }

  collect_workflow_runtime_secrets
  pass "collect_workflow_runtime_secrets skips cleanly when a workflow has no extra runtime secrets"
}

test_write_github_repo_configuration_sets_expected_secrets() {
  local -a calls=()

  gh() {
    calls+=("$*")
  }

  GITHUB_REPO_FULL="acme/demo"
  PROJECT_ID="demo-project"
  PROJECT_NUMBER="123456789"
  WIF_PROVIDER_RESOURCE="projects/123456789/locations/global/workloadIdentityPools/github/providers/demo"
  DEPLOYER_SA_EMAIL="github-deployer@demo-project.iam.gserviceaccount.com"
  RUNTIME_SA_EMAIL="cloudrun-runtime@demo-project.iam.gserviceaccount.com"
  CLIENT_WIF_PROVIDER_SECRET_NAME="GCP_WIF_PROVIDER"
  CLIENT_WIF_SERVICE_ACCOUNT_SECRET_NAME="GCP_WIF_SERVICE_ACCOUNT"
  CLIENT_RUNTIME_SERVICE_ACCOUNT_SECRET_NAME="CLOUD_RUN_RUNTIME_SERVICE_ACCOUNT"
  CLIENT_PROJECT_ID_SECRET_NAME="GCR_PROJECT_ID"
  CLIENT_REGION_SECRET_NAME="GCR_REGION"
  CLIENT_ARTIFACT_PROJECT_SECRET_NAME="GCR_PROJECT_ID"
  CLIENT_ARTIFACT_REGION_SECRET_NAME="GCR_REGION"
  CLIENT_REPOSITORY_SECRET_NAME="GCR_CLIENT_REPOSITORY"
  CLIENT_IMAGE_SECRET_NAME="GCR_IMAGE_NAME"
  REGION="us-central1"
  GAR_REPOSITORY="app-images"
  CLIENT_SERVICE_NAME="demo-app"
  CLIENT_WORKFLOW_EXTRA_SECRET_NAMES=("VITE_API_BASE_URL")
  WORKFLOW_SECRET_VALUE_VITE_API_BASE_URL="https://example.test"

  write_github_repo_configuration

  assert_equals "12" "${#calls[@]}" \
    "write_github_repo_configuration writes project metadata and workflow secrets"
}

run_test test_deployment_target_defaults_to_the_client_workflow
run_test test_repository_deployment_plan_accepts_the_client_shortcut
run_test test_repository_deployment_plan_accepts_the_fullstack_shortcut
run_test test_deployment_target_switches_to_the_service_workflow
run_test test_repository_deployment_plan_schedules_service_before_client_for_fullstack_repos
run_test test_configure_client_workflow_contract_extracts_expected_values
run_test test_configure_client_workflow_contract_requires_workflow_dispatch
run_test test_configure_service_workflow_contract_allows_optional_deploy_flags_to_be_missing
run_test test_collect_workflow_runtime_secrets_skips_cleanly_when_a_workflow_has_no_extra_runtime_secrets
run_test test_write_github_repo_configuration_sets_expected_secrets
