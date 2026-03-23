#!/usr/bin/env bash
# Adds Workload Identity Federation
# When run directly, it prompts for WIF settings and prints the selected pool and provider IDs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "$SCRIPT_DIR/../user-prompts.sh"
fi

wif_pool_exists() {
  gcloud iam workload-identity-pools describe "$1" --location=global >/dev/null 2>&1
}

wif_provider_exists() {
  gcloud iam workload-identity-pools providers describe "$2" \
    --location=global \
    --workload-identity-pool="$1" >/dev/null 2>&1
}

ensure_wif_pool() {
  if ! wif_pool_exists "$WIF_POOL_ID"; then
    gcloud iam workload-identity-pools create "$WIF_POOL_ID" \
      --location=global
  fi
}

ensure_wif_provider() {
  if ! wif_provider_exists "$WIF_POOL_ID" "$WIF_PROVIDER_ID"; then
    gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER_ID" \
      --location=global \
      --workload-identity-pool="$WIF_POOL_ID" \
      --issuer-uri="https://token.actions.githubusercontent.com" \
      --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
      --attribute-condition="attribute.repository=='${GITHUB_REPO_FULL}'"
  else
    info "WIF provider exists: $WIF_PROVIDER_ID"
  fi
}

ensure_wif_service_account_binding() {
  local principal="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/attribute.repository/${GITHUB_REPO_FULL}"

  gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA_EMAIL" \
    --member="$principal" \
    --role="roles/iam.workloadIdentityUser" >/dev/null

  gcloud iam service-accounts add-iam-policy-binding "$DEPLOYER_SA_EMAIL" \
    --member="$principal" \
    --role="roles/iam.serviceAccountTokenCreator" >/dev/null
}

configure_wif() {
  WIF_POOL_ID="${WIF_POOL_ID:-$(prompt_default "WIF Pool" "github-pool")}"
  WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-$(prompt_default "WIF Provider" "${REPO_NAME}-provider")}"

  ensure_wif_pool
  ensure_wif_provider
  ensure_wif_service_account_binding

  WIF_PROVIDER_RESOURCE="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${WIF_POOL_ID}/providers/${WIF_PROVIDER_ID}"
}

wif_main() {
  REPO_NAME="${REPO_NAME:-$(prompt_default "Repo name" "example-repo")}"
  WIF_POOL_ID="$(prompt_default "WIF Pool" "github-pool")"
  WIF_PROVIDER_ID="$(prompt_default "WIF Provider" "${REPO_NAME}-provider")"
  printf "Repo name: %s\n" "$REPO_NAME"
  printf "WIF pool: %s\n" "$WIF_POOL_ID"
  printf "WIF provider: %s\n" "$WIF_PROVIDER_ID"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  wif_main "$@"
fi
