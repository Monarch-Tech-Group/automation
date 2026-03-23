#!/usr/bin/env bash
# Configures the target Google Cloud project and captures its numeric project number.

PROJECT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v info >/dev/null 2>&1; then
  source "$PROJECT_SCRIPT_DIR/../user-prompts.sh"
fi

gcp_project_exists() {
  gcloud projects describe "$1" --format="value(projectId)" >/dev/null 2>&1
}

create_gcp_project() {
  local project_id="$1"
  local project_name="$2"

  info "Creating Google Cloud project: $project_id"
  gcloud projects create "$project_id" --name="$project_name"
}

lookup_project_number() {
  gcloud projects describe "$1" --format="value(projectNumber)"
}

configure_gcp_project() {
  PROJECT_NAME="${PROJECT_NAME:-$(prompt_default "Project name" "${REPO_NAME:-}")}"
  PROJECT_ID="${PROJECT_ID:-$(prompt_default "Project ID" "$(sanitize_project_id "$PROJECT_NAME")")}"

  validate_project_id_format "$PROJECT_ID" \
    || error "Invalid project ID format: $PROJECT_ID"

  if ! gcp_project_exists "$PROJECT_ID"; then
    create_gcp_project "$PROJECT_ID" "$PROJECT_NAME"
  else
    info "Google Cloud project exists: $PROJECT_ID"
  fi

  PROJECT_NUMBER="$(lookup_project_number "$PROJECT_ID")"
  gcloud config set project "$PROJECT_ID" >/dev/null
}
