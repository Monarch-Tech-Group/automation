#!/usr/bin/env bash
# Adds IAM role binding helpers for deployer and runtime service accounts.
# When run directly, it prints the service account plan only.

service_account_exists() {
  gcloud iam service-accounts describe "$1" >/dev/null 2>&1
}

wait_for_service_account() {
  local email="$1"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if service_account_exists "$email"; then
      return 0
    fi

    sleep 2
  done

  error "Service account was created but is not yet available via IAM: $email"
}

ensure_service_account() {
  local service_account_id="$1"
  local display_name="$2"
  local email="${service_account_id}@${PROJECT_ID}.iam.gserviceaccount.com"

  if service_account_exists "$email"; then
    info "Service account exists: $email"
  else
    gcloud iam service-accounts create "$service_account_id" \
      --display-name="$display_name"
    wait_for_service_account "$email"
  fi
}

ensure_project_binding() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="$1" \
    --role="$2" \
    --quiet
}

ensure_service_account_binding() {
  gcloud iam service-accounts add-iam-policy-binding "$1" \
    --member="$2" \
    --role="$3"
}

configure_iam_roles() {
  ensure_service_account "$DEPLOYER_SA_ID" "GitHub deployer"
  ensure_service_account "$RUNTIME_SA_ID" "Cloud Run runtime"

  ensure_project_binding "serviceAccount:${DEPLOYER_SA_EMAIL}" "roles/run.admin"
  ensure_project_binding "serviceAccount:${DEPLOYER_SA_EMAIL}" "roles/artifactregistry.writer"

  ensure_service_account_binding "$RUNTIME_SA_EMAIL" \
    "serviceAccount:${DEPLOYER_SA_EMAIL}" \
    "roles/iam.serviceAccountUser"
}

service_account_main() {
  PROJECT_ID="${PROJECT_ID:-example-project-id}"
  DEPLOYER_SA_EMAIL="${DEPLOYER_SA_EMAIL:-github-deployer@${PROJECT_ID}.iam.gserviceaccount.com}"
  RUNTIME_SA_EMAIL="${RUNTIME_SA_EMAIL:-cloudrun-runtime@${PROJECT_ID}.iam.gserviceaccount.com}"

  printf "Would configure IAM for project: %s\n" "$PROJECT_ID"
  printf "Deployer SA: %s\n" "$DEPLOYER_SA_EMAIL"
  printf "Runtime SA: %s\n" "$RUNTIME_SA_EMAIL"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  service_account_main "$@"
fi
