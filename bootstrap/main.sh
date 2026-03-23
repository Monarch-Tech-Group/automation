#!/usr/bin/env bash
# Orchestrates the full bootstrap flow end-to-end setup of a pipeline from creating your github repo
# All the way through to creating a Google Cloud Project & Pipeline

set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$DIR/scripts/user-prompts.sh"
source "$DIR/scripts/preflight.sh"
source "$DIR/scripts/github.sh"
source "$DIR/scripts/google-cloud/project.sh"
source "$DIR/scripts/google-cloud/gc-service.sh"
source "$DIR/scripts/google-cloud/service-account.sh"
source "$DIR/scripts/google-cloud/wif.sh"
source "$DIR/scripts/output.sh"
source "$DIR/scripts/github-actions.sh"

run_deployment_target() {
  local target_kind="$1"

  unset CLIENT_SERVICE_NAME
  unset CLIENT_WORKFLOW_RUN_ID
  unset CLIENT_WORKFLOW_RUN_URL

  configure_deployment_target "$target_kind"
  configure_client_workflow_contract
  prompt_for_service_configuration
  enable_required_apis
  ensure_artifact_registry_repo
  configure_iam_roles
  configure_wif
  ensure_client_cloud_run_service
  write_github_repo_configuration
  ensure_repo_ready_for_workflow_dispatch
  dispatch_client_deploy_workflow

  if [[ "$target_kind" == "service" ]]; then
    SERVICE_TARGET_SERVICE_NAME="$CLIENT_SERVICE_NAME"
    SERVICE_WORKFLOW_RUN_URL="$CLIENT_WORKFLOW_RUN_URL"
    SERVICE_API_BASE_URL="$(lookup_cloud_run_service_url)"
  else
    CLIENT_TARGET_SERVICE_NAME="$CLIENT_SERVICE_NAME"
  fi
}

main() {
  run_bootstrap_preflight
  ensure_required_tools
  ensure_cli_auth

  configure_github_repo_details
  configure_gcp_project
  ensure_repo_remote

  configure_repository_deployment_plan
  if [[ "$DEPLOYMENT_TARGETS" == *service* ]]; then
    run_deployment_target service
  fi
  if [[ "$DEPLOYMENT_TARGETS" == *client* ]]; then
    if [[ "${REPOSITORY_DEPLOYMENT_KIND:-}" != "fullstack" ]] || prompt_yes_no "Deploy the client now that the service is ready?" "yes"; then
      run_deployment_target client
    fi
  fi
  print_summary
  prompt_for_manual_deploy_test
}

main "$@"
