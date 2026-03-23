#!/usr/bin/env bash
# Outputs Github Variables
# When run directly, it prints a simple summary using example or pre-set environment values.

gh_set_value() {
  gh variable set "$1" --body "$2" --repo "$GITHUB_REPO_FULL"
}

gh_set_secret() {
  gh secret set "$1" --body "$2" --repo "$GITHUB_REPO_FULL"
}

write_github_repo_configuration() {
  gh_set_value "GCP_PROJECT_ID" "$PROJECT_ID"
  gh_set_value "GCP_PROJECT_NUMBER" "$PROJECT_NUMBER"
  gh_set_secret "$CLIENT_WIF_PROVIDER_SECRET_NAME" "$WIF_PROVIDER_RESOURCE"
  gh_set_secret "$CLIENT_WIF_SERVICE_ACCOUNT_SECRET_NAME" "$DEPLOYER_SA_EMAIL"
  gh_set_secret "$CLIENT_RUNTIME_SERVICE_ACCOUNT_SECRET_NAME" "$RUNTIME_SA_EMAIL"
  gh_set_secret "$CLIENT_PROJECT_ID_SECRET_NAME" "$PROJECT_ID"
  gh_set_secret "$CLIENT_REGION_SECRET_NAME" "$REGION"
  gh_set_secret "$CLIENT_ARTIFACT_PROJECT_SECRET_NAME" "$PROJECT_ID"
  gh_set_secret "$CLIENT_ARTIFACT_REGION_SECRET_NAME" "$REGION"
  gh_set_secret "$CLIENT_REPOSITORY_SECRET_NAME" "$GAR_REPOSITORY"
  gh_set_secret "$CLIENT_IMAGE_SECRET_NAME" "$CLIENT_SERVICE_NAME"

  local secret_name
  local secret_value_var
  if declare -p CLIENT_WORKFLOW_EXTRA_SECRET_NAMES >/dev/null 2>&1 && [[ "${#CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[@]}" -gt 0 ]]; then
    for secret_name in "${CLIENT_WORKFLOW_EXTRA_SECRET_NAMES[@]}"; do
      secret_value_var="WORKFLOW_SECRET_VALUE_${secret_name}"
      gh_set_secret "$secret_name" "${!secret_value_var:-${!secret_name:-}}"
    done
  fi
}

print_summary() {
  echo "Repo: $GITHUB_REPO_FULL"
  echo "Project: $PROJECT_ID"
  echo "Region: ${REGION:-n/a}"
  if [[ -n "${SERVICE_TARGET_SERVICE_NAME:-}" ]]; then
    echo "Service deploy target: $SERVICE_TARGET_SERVICE_NAME"
  fi
  if [[ -n "${SERVICE_API_BASE_URL:-}" ]]; then
    echo "Service URL: $SERVICE_API_BASE_URL"
  fi
  if [[ -n "${SERVICE_WORKFLOW_RUN_URL:-}" ]]; then
    echo "Service workflow URL: $SERVICE_WORKFLOW_RUN_URL"
  fi
  if [[ -n "${CLIENT_TARGET_SERVICE_NAME:-}" ]]; then
    echo "Client deploy target: $CLIENT_TARGET_SERVICE_NAME"
  fi
  if [[ -n "${CLIENT_WORKFLOW_RUN_URL:-}" ]]; then
    echo "Client workflow URL: $CLIENT_WORKFLOW_RUN_URL"
  fi
}

output_main() {
  GITHUB_REPO_FULL="${GITHUB_REPO_FULL:-example-org/example-repo}"
  PROJECT_ID="${PROJECT_ID:-example-project-id}"
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  output_main "$@"
fi
