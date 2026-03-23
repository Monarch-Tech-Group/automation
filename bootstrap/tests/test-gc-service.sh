#!/usr/bin/env bash
# Tests Cloud Run and Artifact Registry bootstrap helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/google-cloud/gc-service.sh"

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

test_service_configuration_uses_project_and_repository_defaults() {
  PROJECT_ID="demo-project"
  REPO_NAME="survey-app"
  CLIENT_SERVICE_DEFAULT_NAME="demo-project-client"
  DEPLOYMENT_TARGET_KIND="client"
  unset REGION GAR_REPOSITORY CLIENT_SERVICE_NAME DEPLOYER_SA_ID RUNTIME_SA_ID || true

  workflow_requires_secret() {
    return 1
  }

  collect_workflow_runtime_secrets() {
    return 0
  }

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"
    printf '%s' "$default"
  }

  prompt_for_service_configuration

  assert_equals "us-central1" "$REGION" \
    "service configuration defaults the deploy region"
  assert_equals "demo-project" "$GAR_REPOSITORY" \
    "service configuration defaults the Artifact Registry repository to the project identifier"
  assert_equals "demo-project-client" "$CLIENT_SERVICE_NAME" \
    "service configuration defaults the Cloud Run service name from the selected service kind"
  assert_equals "github-deployer@demo-project.iam.gserviceaccount.com" "$DEPLOYER_SA_EMAIL" \
    "service configuration derives the deployer service account email from the project"
}

test_artifact_registry_creation_is_skipped_when_the_repository_exists() {
  local created=0

  GAR_REPOSITORY="app-images"
  REGION="us-central1"

  artifact_repo_exists() {
    return 0
  }

  gcloud() {
    created=1
  }

  ensure_artifact_registry_repo

  assert_equals "0" "$created" \
    "artifact repository creation is skipped when the repository already exists"
}

test_cloud_run_service_creation_includes_workflow_pinned_flags() {
  local command_text=""
  local iam_binding_text=""

  CLIENT_SERVICE_NAME="survey-app"
  REGION="us-central1"
  CLIENT_SERVICE_PORT="80"
  CLIENT_SERVICE_CPU="0.08"
  CLIENT_SERVICE_MEMORY="128Mi"
  CLIENT_SERVICE_CONCURRENCY="1"
  CLIENT_SERVICE_MIN_INSTANCES="0"
  CLIENT_SERVICE_MAX_INSTANCES="1"
  CLIENT_SERVICE_EXECUTION_ENVIRONMENT="gen1"
  CLIENT_SERVICE_ALLOW_UNAUTHENTICATED=1
  CLIENT_SERVICE_CPU_THROTTLING=1
  RUNTIME_SA_EMAIL="runtime@demo-project.iam.gserviceaccount.com"

  client_cloud_run_service_exists() {
    return 1
  }

  gcloud() {
    if [[ "$1 $2 $3" == "run deploy survey-app" ]]; then
      command_text="$*"
      return 0
    fi

    if [[ "$1 $2 $3 $4" == "run services add-iam-policy-binding survey-app" ]]; then
      iam_binding_text="$*"
      return 0
    fi
  }

  ensure_client_cloud_run_service

  case "$command_text" in
    *"run deploy survey-app"* ) ;;
    * )
      fail "Cloud Run provisioning should deploy the expected service name"
      ;;
  esac

  case "$command_text" in
    *"--allow-unauthenticated"* ) ;;
    * )
      fail "Cloud Run provisioning should include public access when the workflow requires it"
      ;;
  esac

  case "$command_text" in
    *"--cpu-throttling"* ) ;;
    * )
      fail "Cloud Run provisioning should include CPU throttling when the workflow requires it"
      ;;
  esac

  case "$command_text" in
    *"--command sh"* ) ;;
    * )
      fail "Cloud Run provisioning should use the bootstrap placeholder command that can listen on the requested port"
      ;;
  esac

  case "$command_text" in
    *"--args=-c,python -m http.server \${PORT:-8080}"* ) ;;
    * )
      fail "Cloud Run provisioning should use placeholder args that honor Cloud Run's PORT environment variable"
      ;;
  esac

  case "$iam_binding_text" in
    *"--member=allUsers"* ) ;;
    * )
      fail "Cloud Run provisioning should explicitly grant public invoker access when the workflow requires it"
      ;;
  esac

  pass "Cloud Run provisioning carries the workflow-pinned deploy flags"
}

test_service_configuration_reuses_the_service_url_for_client_runtime_input() {
  PROJECT_ID="demo-project"
  CLIENT_SERVICE_DEFAULT_NAME="demo-project-client"
  DEPLOYMENT_TARGET_KIND="client"
  SERVICE_API_BASE_URL="https://demo-project-service.a.run.app"
  CLIENT_WORKFLOW_EXTRA_SECRET_NAMES=("VITE_API_BASE_URL")
  unset WORKFLOW_SECRET_VALUE_VITE_API_BASE_URL REGION GAR_REPOSITORY CLIENT_SERVICE_NAME DEPLOYER_SA_ID RUNTIME_SA_ID || true

  workflow_requires_secret() {
    [[ "$1" == "VITE_API_BASE_URL" ]]
  }

  collect_workflow_runtime_secrets() {
    return 0
  }

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"
    printf '%s' "$default"
  }

  prompt_for_service_configuration

  assert_equals "https://demo-project-service.a.run.app" "$WORKFLOW_SECRET_VALUE_VITE_API_BASE_URL" \
    "service configuration reuses the deployed service URL for the client API base URL"
}

test_service_configuration_reasks_when_the_google_cloud_location_is_invalid() {
  local temp_dir region_attempt_file

  temp_dir="$(mktemp -d)"
  region_attempt_file="$temp_dir/region-attempted"

  PROJECT_ID="demo-project"
  CLIENT_SERVICE_DEFAULT_NAME="demo-project-service"
  DEPLOYMENT_TARGET_KIND="service"
  unset REGION GAR_REPOSITORY CLIENT_SERVICE_NAME DEPLOYER_SA_ID RUNTIME_SA_ID || true

  workflow_requires_secret() {
    return 1
  }

  collect_workflow_runtime_secrets() {
    return 0
  }

  prompt_default() {
    local prompt="$1"
    local default="${2:-}"

    if [[ "$prompt" == "Region" ]]; then
      if [[ ! -f "$region_attempt_file" ]]; then
        : > "$region_attempt_file"
        printf 'b'
      else
        printf 'us-central1'
      fi
      return 0
    fi

    printf '%s' "$default"
  }

  prompt_for_service_configuration

  assert_equals "us-central1" "$REGION" \
    "service configuration re-asks until it receives a valid Google Cloud region"

  rm -rf "$temp_dir"
}

run_test test_service_configuration_uses_project_and_repository_defaults
run_test test_artifact_registry_creation_is_skipped_when_the_repository_exists
run_test test_cloud_run_service_creation_includes_workflow_pinned_flags
run_test test_service_configuration_reuses_the_service_url_for_client_runtime_input
run_test test_service_configuration_reasks_when_the_google_cloud_location_is_invalid
