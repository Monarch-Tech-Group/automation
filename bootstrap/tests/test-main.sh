#!/usr/bin/env bash
# Tests the bootstrap entrypoint orchestration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

write_stub_script() {
  local path="$1"
  local body="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<EOF
#!/usr/bin/env bash
$body
EOF
}

test_bootstrap_entrypoint_runs_the_expected_steps_in_order() {
  local temp_bootstrap log_file actual

  temp_bootstrap="$(mktemp -d)"
  log_file="$temp_bootstrap/calls.log"
  cp "$BOOTSTRAP_ROOT/main.sh" "$temp_bootstrap/main.sh"

  write_stub_script "$temp_bootstrap/scripts/user-prompts.sh" '
step() { printf "%s|" "$1" >> "$BOOTSTRAP_TEST_LOG"; }
prompt_yes_no() { return 1; }
'
  write_stub_script "$temp_bootstrap/scripts/preflight.sh" '
run_bootstrap_preflight() { step preflight; }
'
  write_stub_script "$temp_bootstrap/scripts/github.sh" '
ensure_required_tools() { step tools; }
ensure_cli_auth() { step auth; }
configure_github_repo_details() { step github; }
ensure_repo_remote() { step remote; }
ensure_repo_ready_for_workflow_dispatch() { step dispatch-ready; }
prompt_for_manual_deploy_test() { step manual-test; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/project.sh" '
configure_gcp_project() { step project; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/gc-service.sh" '
prompt_for_service_configuration() { CLIENT_SERVICE_NAME="demo-target"; step service-config; }
enable_required_apis() { step apis; }
ensure_artifact_registry_repo() { step artifact; }
ensure_client_cloud_run_service() { step cloud-run; }
lookup_cloud_run_service_url() { printf "https://service.example.test\n"; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/service-account.sh" '
configure_iam_roles() { step iam; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/wif.sh" '
configure_wif() { step wif; }
'
  write_stub_script "$temp_bootstrap/scripts/output.sh" '
write_github_repo_configuration() { step repo-config; }
print_summary() { step summary; }
'
  write_stub_script "$temp_bootstrap/scripts/github-actions.sh" '
configure_repository_deployment_plan() { step deployment-plan; DEPLOYMENT_TARGETS="client"; REPOSITORY_DEPLOYMENT_KIND="client"; }
configure_deployment_target() { step deployment-target; }
configure_client_workflow_contract() { step workflow; }
dispatch_client_deploy_workflow() { CLIENT_WORKFLOW_RUN_URL="https://github.com/acme/demo/actions/runs/1"; step dispatch; }
'
  chmod +x "$temp_bootstrap/main.sh"

  BOOTSTRAP_TEST_LOG="$log_file" bash "$temp_bootstrap/main.sh"
  actual="$(cat "$log_file")"

  assert_equals \
    "preflight|tools|auth|github|project|remote|deployment-plan|deployment-target|workflow|service-config|apis|artifact|iam|wif|cloud-run|repo-config|dispatch-ready|dispatch|summary|manual-test|" \
    "$actual" \
    "bootstrap entrypoint orchestrates the live setup flow in the intended order"

  rm -rf "$temp_bootstrap"
}

test_bootstrap_entrypoint_runs_service_then_client_for_fullstack_repositories() {
  local temp_bootstrap log_file actual

  temp_bootstrap="$(mktemp -d)"
  log_file="$temp_bootstrap/calls.log"
  cp "$BOOTSTRAP_ROOT/main.sh" "$temp_bootstrap/main.sh"

  write_stub_script "$temp_bootstrap/scripts/user-prompts.sh" '
step() { printf "%s|" "$1" >> "$BOOTSTRAP_TEST_LOG"; }
prompt_yes_no() {
  if [[ "$1" == "Deploy the client now that the service is ready?" ]]; then
    step client-confirm
    return 0
  fi
  return 1
}
'
  write_stub_script "$temp_bootstrap/scripts/preflight.sh" '
run_bootstrap_preflight() { step preflight; }
'
  write_stub_script "$temp_bootstrap/scripts/github.sh" '
ensure_required_tools() { step tools; }
ensure_cli_auth() { step auth; }
configure_github_repo_details() { step github; }
ensure_repo_remote() { step remote; }
ensure_repo_ready_for_workflow_dispatch() { step dispatch-ready; }
prompt_for_manual_deploy_test() { step manual-test; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/project.sh" '
configure_gcp_project() { step project; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/gc-service.sh" '
prompt_for_service_configuration() { CLIENT_SERVICE_NAME="${DEPLOYMENT_TARGET_KIND}-target"; step service-config-"$DEPLOYMENT_TARGET_KIND"; }
enable_required_apis() { step apis-"$DEPLOYMENT_TARGET_KIND"; }
ensure_artifact_registry_repo() { step artifact-"$DEPLOYMENT_TARGET_KIND"; }
ensure_client_cloud_run_service() { step cloud-run-"$DEPLOYMENT_TARGET_KIND"; }
lookup_cloud_run_service_url() { printf "https://service.example.test\n"; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/service-account.sh" '
configure_iam_roles() { step iam-"$DEPLOYMENT_TARGET_KIND"; }
'
  write_stub_script "$temp_bootstrap/scripts/google-cloud/wif.sh" '
configure_wif() { step wif-"$DEPLOYMENT_TARGET_KIND"; }
'
  write_stub_script "$temp_bootstrap/scripts/output.sh" '
write_github_repo_configuration() { step repo-config-"$DEPLOYMENT_TARGET_KIND"; }
print_summary() { step summary; }
'
  write_stub_script "$temp_bootstrap/scripts/github-actions.sh" '
configure_repository_deployment_plan() { step deployment-plan; DEPLOYMENT_TARGETS="service client"; REPOSITORY_DEPLOYMENT_KIND="fullstack"; }
configure_deployment_target() { DEPLOYMENT_TARGET_KIND="$1"; step deployment-target-"$1"; }
configure_client_workflow_contract() { step workflow-"$DEPLOYMENT_TARGET_KIND"; }
dispatch_client_deploy_workflow() { CLIENT_WORKFLOW_RUN_URL="https://github.com/acme/demo/actions/runs/1"; step dispatch-"$DEPLOYMENT_TARGET_KIND"; }
'
  chmod +x "$temp_bootstrap/main.sh"

  BOOTSTRAP_TEST_LOG="$log_file" bash "$temp_bootstrap/main.sh"
  actual="$(cat "$log_file")"

  assert_equals \
    "preflight|tools|auth|github|project|remote|deployment-plan|deployment-target-service|workflow-service|service-config-service|apis-service|artifact-service|iam-service|wif-service|cloud-run-service|repo-config-service|dispatch-ready|dispatch-service|client-confirm|deployment-target-client|workflow-client|service-config-client|apis-client|artifact-client|iam-client|wif-client|cloud-run-client|repo-config-client|dispatch-ready|dispatch-client|summary|manual-test|" \
    "$actual" \
    "bootstrap entrypoint runs the service deployment before the client deployment for fullstack repositories"

  rm -rf "$temp_bootstrap"
}

run_test test_bootstrap_entrypoint_runs_the_expected_steps_in_order
run_test test_bootstrap_entrypoint_runs_service_then_client_for_fullstack_repositories
