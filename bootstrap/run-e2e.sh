#!/usr/bin/env bash
# Runs bootstrap end to end using environment variables instead of interactive prompts.

set -Eeuo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$BOOTSTRAP_DIR/scripts/user-prompts.sh"

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || error "Missing required environment variable: $name"
}

main() {
  require_env GITHUB_REPO_FULL
  require_env PROJECT_ID
  require_env VITE_API_BASE_URL

  export GITHUB_OWNER="${GITHUB_OWNER:-${GITHUB_REPO_FULL%%/*}}"
  export REPO_NAME="${REPO_NAME:-${GITHUB_REPO_FULL##*/}}"
  export PROJECT_NAME="${PROJECT_NAME:-$REPO_NAME}"
  export REGION="${REGION:-us-central1}"
  export GAR_REPOSITORY="${GAR_REPOSITORY:-app-images}"
  export CLIENT_SERVICE_NAME="${CLIENT_SERVICE_NAME:-$REPO_NAME}"
  export DEPLOYER_SA_ID="${DEPLOYER_SA_ID:-github-deployer}"
  export RUNTIME_SA_ID="${RUNTIME_SA_ID:-cloudrun-runtime}"
  export WIF_POOL_ID="${WIF_POOL_ID:-github}"
  export WIF_PROVIDER_ID="${WIF_PROVIDER_ID:-$REPO_NAME}"

  "$BOOTSTRAP_DIR/main.sh"
}

main "$@"
