#!/usr/bin/env bash
# Adds Cloud Run and Artifact Registry configuration.
# When run directly, it prompts for service settings and prints the derived values.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "$SCRIPT_DIR/../user-prompts.sh"
fi

BOOTSTRAP_PLACEHOLDER_IMAGE="${BOOTSTRAP_PLACEHOLDER_IMAGE:-python:3.12-slim}"
BOOTSTRAP_PLACEHOLDER_COMMAND="${BOOTSTRAP_PLACEHOLDER_COMMAND:-sh}"
BOOTSTRAP_PLACEHOLDER_ARGS="${BOOTSTRAP_PLACEHOLDER_ARGS:--c,python -m http.server \${PORT:-8080}}"

enable_required_apis() {
  gcloud services enable \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com \
    artifactregistry.googleapis.com \
    run.googleapis.com \
    cloudbuild.googleapis.com
}

artifact_repo_exists() {
  gcloud artifacts repositories describe "$1" --location="$2" >/dev/null 2>&1
}

ensure_artifact_registry_repo() {
  if artifact_repo_exists "$GAR_REPOSITORY" "$REGION"; then
    info "Artifact repo exists"
  else
    gcloud artifacts repositories create "$GAR_REPOSITORY" \
      --location="$REGION" \
      --repository-format="docker"
  fi
}

lookup_cloud_run_service_url() {
  gcloud run services describe "$CLIENT_SERVICE_NAME" \
    --region="$REGION" \
    --format="value(status.url)"
}

prepare_target_runtime_inputs() {
  if [[ "${DEPLOYMENT_TARGET_KIND:-}" == "client" && -n "${SERVICE_API_BASE_URL:-}" ]] && workflow_requires_secret "VITE_API_BASE_URL"; then
    WORKFLOW_SECRET_VALUE_VITE_API_BASE_URL="$SERVICE_API_BASE_URL"
  fi
}

validate_gcp_location() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$ ]]
}

prompt_for_gcp_location() {
  local default_location="${1:-us-central1}"
  local selected_location

  while true; do
    selected_location="$(prompt_default "Region" "$default_location")"
    if validate_gcp_location "$selected_location"; then
      printf '%s' "$selected_location"
      return 0
    fi

    warn "Invalid Google Cloud region/location: $selected_location"
  done
}

prompt_for_service_configuration() {
  REGION="${REGION:-$(prompt_for_gcp_location "${CLIENT_SERVICE_REGION_DEFAULT:-us-central1}")}"
  GAR_REPOSITORY="${GAR_REPOSITORY:-$(prompt_default "Artifact repo" "${PROJECT_ID}")}"
  CLIENT_SERVICE_NAME="${CLIENT_SERVICE_NAME:-$(prompt_default "Cloud Run service name" "${CLIENT_SERVICE_DEFAULT_NAME:-${PROJECT_ID}}")}"

  DEPLOYER_SA_ID="${DEPLOYER_SA_ID:-$(prompt_default "Deployer SA" "github-deployer")}"
  RUNTIME_SA_ID="${RUNTIME_SA_ID:-$(prompt_default "Runtime SA" "cloudrun-runtime")}"

  DEPLOYER_SA_EMAIL="${DEPLOYER_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
  RUNTIME_SA_EMAIL="${RUNTIME_SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"

  prepare_target_runtime_inputs
  collect_workflow_runtime_secrets
}

gc_service_main() {
  PROJECT_ID="${PROJECT_ID:-$(prompt_required "Project ID")}"
  prompt_for_service_configuration
  printf "Project ID: %s\n" "$PROJECT_ID"
  printf "Region: %s\n" "$REGION"
  printf "Artifact repo: %s\n" "$GAR_REPOSITORY"
  printf "Cloud Run service: %s\n" "$CLIENT_SERVICE_NAME"
  printf "Deployer SA: %s\n" "$DEPLOYER_SA_EMAIL"
  printf "Runtime SA: %s\n" "$RUNTIME_SA_EMAIL"
}

client_cloud_run_service_exists() {
  gcloud run services describe "$CLIENT_SERVICE_NAME" --region="$REGION" >/dev/null 2>&1
}

ensure_client_cloud_run_service() {
  local -a cmd

  cmd=(
    gcloud run deploy "$CLIENT_SERVICE_NAME"
    --image "$BOOTSTRAP_PLACEHOLDER_IMAGE"
    --region "$REGION"
    --port "$CLIENT_SERVICE_PORT"
    --platform managed
    --service-account "$RUNTIME_SA_EMAIL"
    --command "$BOOTSTRAP_PLACEHOLDER_COMMAND"
    "--args=${BOOTSTRAP_PLACEHOLDER_ARGS}"
    --quiet
  )

  if [[ -n "${CLIENT_SERVICE_CPU:-}" ]]; then
    cmd+=(--cpu "$CLIENT_SERVICE_CPU")
  fi

  if [[ -n "${CLIENT_SERVICE_MEMORY:-}" ]]; then
    cmd+=(--memory "$CLIENT_SERVICE_MEMORY")
  fi

  if [[ -n "${CLIENT_SERVICE_CONCURRENCY:-}" ]]; then
    cmd+=(--concurrency "$CLIENT_SERVICE_CONCURRENCY")
  fi

  if [[ -n "${CLIENT_SERVICE_MIN_INSTANCES:-}" ]]; then
    cmd+=(--min-instances "$CLIENT_SERVICE_MIN_INSTANCES")
  fi

  if [[ -n "${CLIENT_SERVICE_MAX_INSTANCES:-}" ]]; then
    cmd+=(--max-instances "$CLIENT_SERVICE_MAX_INSTANCES")
  fi

  if [[ -n "${CLIENT_SERVICE_EXECUTION_ENVIRONMENT:-}" ]]; then
    cmd+=(--execution-environment "$CLIENT_SERVICE_EXECUTION_ENVIRONMENT")
  fi

  if [[ "${CLIENT_SERVICE_ALLOW_UNAUTHENTICATED:-0}" == "1" ]]; then
    cmd+=(--allow-unauthenticated)
  fi

  if [[ "${CLIENT_SERVICE_CPU_THROTTLING:-0}" == "1" ]]; then
    cmd+=(--cpu-throttling)
  fi

  if client_cloud_run_service_exists; then
    info "Cloud Run service exists. Reconciling pinned settings for $CLIENT_SERVICE_NAME"
  else
    info "Creating Cloud Run service: $CLIENT_SERVICE_NAME"
  fi

  "${cmd[@]}"

  if [[ "${CLIENT_SERVICE_ALLOW_UNAUTHENTICATED:-0}" == "1" ]]; then
    if ! gcloud run services add-iam-policy-binding "$CLIENT_SERVICE_NAME" \
      --region "$REGION" \
      --member="allUsers" \
      --role="roles/run.invoker" \
      >/dev/null; then
      warn "Public access could not be granted to $CLIENT_SERVICE_NAME. An organization policy may block allUsers bindings."
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  gc_service_main "$@"
fi
