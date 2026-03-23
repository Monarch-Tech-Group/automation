#!/usr/bin/env bash
# Parses the client deploy workflow and validates it via the GitHub CLI.

GITHUB_ACTIONS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v info >/dev/null 2>&1; then
  source "$GITHUB_ACTIONS_SCRIPT_DIR/user-prompts.sh"
fi

CLIENT_WORKFLOW_PATH="${CLIENT_WORKFLOW_PATH:-.github/workflows/client-deploy.yml}"
CLIENT_WORKFLOW_FILENAME="$(basename "$CLIENT_WORKFLOW_PATH")"

configure_repository_deployment_plan() {
  REPOSITORY_DEPLOYMENT_KIND="${REPOSITORY_DEPLOYMENT_KIND:-$(prompt_default "Repository deploy type (s=server, c=client, b=both)" "s")}"
  REPOSITORY_DEPLOYMENT_KIND="$(printf '%s' "$REPOSITORY_DEPLOYMENT_KIND" | tr '[:upper:]' '[:lower:]')"

  case "$REPOSITORY_DEPLOYMENT_KIND" in
    client|c)
      REPOSITORY_DEPLOYMENT_KIND="client"
      DEPLOYMENT_TARGETS="client"
      ;;
    service|server|s)
      REPOSITORY_DEPLOYMENT_KIND="service"
      DEPLOYMENT_TARGETS="service"
      ;;
    fullstack|both|b)
      REPOSITORY_DEPLOYMENT_KIND="fullstack"
      DEPLOYMENT_TARGETS="service client"
      ;;
    *)
      error "Unsupported repository deploy type: $REPOSITORY_DEPLOYMENT_KIND"
      ;;
  esac
}

configure_deployment_target() {
  DEPLOYMENT_TARGET_KIND="$1"

  case "$DEPLOYMENT_TARGET_KIND" in
    client)
      CLIENT_WORKFLOW_PATH=".github/workflows/client-deploy.yml"
      CLIENT_SERVICE_DEFAULT_NAME="${PROJECT_ID}-client"
      ;;
    service)
      CLIENT_WORKFLOW_PATH=".github/workflows/service-deploy.yml"
      CLIENT_SERVICE_DEFAULT_NAME="${PROJECT_ID}-service"
      ;;
    *)
      error "Unsupported deployment target: $DEPLOYMENT_TARGET_KIND"
      ;;
  esac

  CLIENT_WORKFLOW_FILENAME="$(basename "$CLIENT_WORKFLOW_PATH")"
}

require_workflow_file() {
  [[ -f "$CLIENT_WORKFLOW_PATH" ]] || error "Workflow file not found: $CLIENT_WORKFLOW_PATH"
}

workflow_has_dispatch() {
  rg -q '^[[:space:]]+workflow_dispatch:' "$CLIENT_WORKFLOW_PATH"
}

workflow_uses_gcloud_run_deploy() {
  rg -q 'gcloud run deploy' "$CLIENT_WORKFLOW_PATH"
}

extract_secret_name_for_key() {
  local key="$1"
  local line

  line="$(rg -n -m1 "${key}:[[:space:]]*\\$\\{\\{ secrets\\.[A-Z0-9_]+ \\}\\}" "$CLIENT_WORKFLOW_PATH" || true)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line" | sed -E 's/.*secrets\.([A-Z0-9_]+).*/\1/'
}

extract_secret_name_for_flag() {
  local flag="$1"
  local line

  line="$(rg -n -m1 -- "${flag}([[:space:]]+|=)[\"']?[$][{][{][[:space:]]*secrets\\.[A-Z0-9_]+[[:space:]]*[}][}][\"']?" "$CLIENT_WORKFLOW_PATH" || true)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line" | sed -E 's/.*secrets\.([A-Z0-9_]+).*/\1/'
}

extract_secret_refs_from_line() {
  printf '%s\n' "$1" | grep -oE 'secrets\.[A-Z0-9_]+' | sed 's/secrets\.//'
}

extract_image_reference_secrets() {
  local line
  local -a refs=()

  while IFS= read -r line; do
    refs=()
    append_lines_to_array refs < <(extract_secret_refs_from_line "$line")
    if [[ "${#refs[@]}" -ge 4 ]]; then
      printf '%s\n' "${refs[@]}"
      return 0
    fi
  done < <(rg -n 'docker\.pkg\.dev/' "$CLIENT_WORKFLOW_PATH" || true)

  return 1
}

extract_secret_name_from_deploy_line() {
  local line

  line="$(rg -n -m1 'gcloud run deploy.*secrets\.[A-Z0-9_]+' "$CLIENT_WORKFLOW_PATH" || true)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line" | sed -E 's/.*gcloud run deploy "?[$][{][{] secrets\.([A-Z0-9_]+) [}][}]?"?.*/\1/'
}

extract_literal_flag_value() {
  local flag="$1"
  local line

  line="$(rg -n -m1 -- "${flag}[=[:space:]\"]" "$CLIENT_WORKFLOW_PATH" || true)"
  [[ -n "$line" ]] || return 1
  printf '%s\n' "$line" | sed -E "s/.*${flag}[=[:space:]\"]+([^ \"\\\\]+).*/\\1/"
}

extract_optional_literal_flag_value() {
  local flag="$1"

  extract_literal_flag_value "$flag" || true
}

workflow_sets_allow_unauthenticated() {
  rg -q -- '--allow-unauthenticated' "$CLIENT_WORKFLOW_PATH"
}

workflow_sets_cpu_throttling() {
  rg -q -- '--cpu-throttling' "$CLIENT_WORKFLOW_PATH"
}

collect_workflow_secret_names() {
  rg -o 'secrets\.[A-Z0-9_]+' "$CLIENT_WORKFLOW_PATH" | sed 's/secrets\.//' | sort -u
}

append_lines_to_array() {
  local target_array="$1"
  local line

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    eval "$target_array+=(\"\$line\")"
  done
}

workflow_secret_is_managed_by_github() {
  case "$1" in
    GITHUB_TOKEN)
      return 0
      ;;
  esac

  return 1
}

workflow_has_extra_secret_names() {
  declare -p CLIENT_WORKFLOW_EXTRA_SECRET_NAMES >/dev/null 2>&1 || return 1
  [[ "${#CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[@]}" -gt 0 ]]
}

configure_client_workflow_contract() {
  local service_secret
  local region_secret
  local project_secret
  local wif_provider_secret
  local wif_service_account_secret
  local runtime_service_account_secret
  local -a image_secrets=()
  local -a workflow_secrets=()
  local secret_name
  local managed_secret

  CLIENT_WORKFLOW_FILENAME="$(basename "$CLIENT_WORKFLOW_PATH")"
  require_workflow_file
  workflow_has_dispatch || error "$CLIENT_WORKFLOW_FILENAME must declare workflow_dispatch for gh workflow run"
  workflow_uses_gcloud_run_deploy || error "$CLIENT_WORKFLOW_FILENAME must contain a gcloud run deploy step"

  service_secret="$(extract_secret_name_from_deploy_line)" \
    || error "Unable to determine the Cloud Run service secret from $CLIENT_WORKFLOW_FILENAME"
  region_secret="$(extract_secret_name_for_flag '--region' || true)"
  [[ -n "${region_secret:-}" ]] || error "Unable to determine the deploy region secret from $CLIENT_WORKFLOW_FILENAME"

  project_secret="$(extract_secret_name_for_key "project_id")" \
    || error "Unable to determine the GCP project secret from $CLIENT_WORKFLOW_FILENAME"
  wif_provider_secret="$(extract_secret_name_for_key "workload_identity_provider")" \
    || error "Unable to determine the WIF provider secret from $CLIENT_WORKFLOW_FILENAME"
  wif_service_account_secret="$(extract_secret_name_for_key "service_account")" \
    || error "Unable to determine the WIF service account secret from $CLIENT_WORKFLOW_FILENAME"
  runtime_service_account_secret="$(extract_secret_name_for_flag '--service-account' || true)"
  [[ -n "${runtime_service_account_secret:-}" ]] || error "Unable to determine the Cloud Run runtime service account secret from $CLIENT_WORKFLOW_FILENAME"

  append_lines_to_array image_secrets < <(extract_image_reference_secrets)
  [[ "${#image_secrets[@]}" -ge 4 ]] || error "Unable to determine Artifact Registry secrets from $CLIENT_WORKFLOW_FILENAME"

  CLIENT_SERVICE_NAME_SECRET_NAME="$service_secret"
  CLIENT_REGION_SECRET_NAME="$region_secret"
  CLIENT_PROJECT_ID_SECRET_NAME="$project_secret"
  CLIENT_WIF_PROVIDER_SECRET_NAME="$wif_provider_secret"
  CLIENT_WIF_SERVICE_ACCOUNT_SECRET_NAME="$wif_service_account_secret"
  CLIENT_RUNTIME_SERVICE_ACCOUNT_SECRET_NAME="$runtime_service_account_secret"
  CLIENT_ARTIFACT_REGION_SECRET_NAME="${image_secrets[0]}"
  CLIENT_ARTIFACT_PROJECT_SECRET_NAME="${image_secrets[1]}"
  CLIENT_REPOSITORY_SECRET_NAME="${image_secrets[2]}"
  CLIENT_IMAGE_SECRET_NAME="${image_secrets[3]}"

  CLIENT_SERVICE_PORT="$(extract_literal_flag_value '--port')"
  CLIENT_SERVICE_CPU="$(extract_optional_literal_flag_value '--cpu')"
  CLIENT_SERVICE_MEMORY="$(extract_optional_literal_flag_value '--memory')"
  CLIENT_SERVICE_CONCURRENCY="$(extract_optional_literal_flag_value '--concurrency')"
  CLIENT_SERVICE_MIN_INSTANCES="$(extract_optional_literal_flag_value '--min-instances')"
  CLIENT_SERVICE_MAX_INSTANCES="$(extract_optional_literal_flag_value '--max-instances')"
  CLIENT_SERVICE_EXECUTION_ENVIRONMENT="$(extract_optional_literal_flag_value '--execution-environment')"
  CLIENT_SERVICE_ALLOW_UNAUTHENTICATED=0
  CLIENT_SERVICE_CPU_THROTTLING=0
  workflow_sets_allow_unauthenticated && CLIENT_SERVICE_ALLOW_UNAUTHENTICATED=1
  workflow_sets_cpu_throttling && CLIENT_SERVICE_CPU_THROTTLING=1

  append_lines_to_array workflow_secrets < <(collect_workflow_secret_names)
  CLIENT_WORKFLOW_EXTRA_SECRET_NAMES=()
  for secret_name in "${workflow_secrets[@]}"; do
    managed_secret=0
    case "$secret_name" in
      "$CLIENT_SERVICE_NAME_SECRET_NAME"|"$CLIENT_REGION_SECRET_NAME"|"$CLIENT_PROJECT_ID_SECRET_NAME"|"$CLIENT_WIF_PROVIDER_SECRET_NAME"|"$CLIENT_WIF_SERVICE_ACCOUNT_SECRET_NAME"|"$CLIENT_RUNTIME_SERVICE_ACCOUNT_SECRET_NAME"|"$CLIENT_REPOSITORY_SECRET_NAME"|"$CLIENT_IMAGE_SECRET_NAME")
        managed_secret=1
        ;;
    esac

    if workflow_secret_is_managed_by_github "$secret_name"; then
      managed_secret=1
    fi

    if [[ "$managed_secret" -eq 0 ]]; then
      CLIENT_WORKFLOW_EXTRA_SECRET_NAMES+=("$secret_name")
    fi
  done
}

set_workflow_extra_secret_value() {
  local secret_name="$1"
  local prompt_label="$2"
  local secret_value

  secret_value="$(prompt_required "$prompt_label")"
  printf -v "WORKFLOW_SECRET_VALUE_${secret_name}" '%s' "$secret_value"
}

collect_workflow_runtime_secrets() {
  local secret_name
  local prompt_label
  local secret_value_var

  workflow_has_extra_secret_names || return 0

  for secret_name in "${CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[@]}"; do
    case "$secret_name" in
      VITE_API_BASE_URL)
        prompt_label="VITE API Base URL"
        ;;
      *)
        prompt_label="$secret_name"
        ;;
    esac

    secret_value_var="WORKFLOW_SECRET_VALUE_${secret_name}"
    if [[ -z "${!secret_name:-}" && -z "${!secret_value_var:-}" ]]; then
      set_workflow_extra_secret_value "$secret_name" "$prompt_label"
    fi
  done
}

workflow_requires_secret() {
  local secret_name="$1"
  local known_secret

  workflow_has_extra_secret_names || return 1

  for known_secret in "${CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[@]}"; do
    if [[ "$known_secret" == "$secret_name" ]]; then
      return 0
    fi
  done

  return 1
}

ensure_remote_client_workflow() {
  gh workflow view "$CLIENT_WORKFLOW_FILENAME" --repo "$GITHUB_REPO_FULL" >/dev/null 2>&1 \
    || error "Remote workflow not found via gh: $CLIENT_WORKFLOW_FILENAME. Push the workflow to GitHub before validation."
}

dispatch_client_deploy_workflow() {
  local run_id

  ensure_remote_client_workflow

  info "Dispatching GitHub Actions workflow: $CLIENT_WORKFLOW_FILENAME"
  gh workflow run "$CLIENT_WORKFLOW_FILENAME" --repo "$GITHUB_REPO_FULL" --ref main >/dev/null

  run_id="$(gh run list \
    --repo "$GITHUB_REPO_FULL" \
    --workflow "$CLIENT_WORKFLOW_FILENAME" \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')"
  [[ -n "$run_id" && "$run_id" != "null" ]] || error "Unable to determine the dispatched workflow run ID"

  CLIENT_WORKFLOW_RUN_ID="$run_id"
  CLIENT_WORKFLOW_RUN_URL="https://github.com/${GITHUB_REPO_FULL}/actions/runs/${CLIENT_WORKFLOW_RUN_ID}"

  gh run watch "$CLIENT_WORKFLOW_RUN_ID" --repo "$GITHUB_REPO_FULL" --exit-status
}
