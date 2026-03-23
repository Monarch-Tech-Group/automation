#!/usr/bin/env bash
# Tests bootstrap preflight checks and messaging.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/preflight.sh"

pass() {
  printf "✅ %s\n" "$1"
}

fail() {
  printf "❌ %s\n" "$1" >&2
  exit 1
}

run_test() {
  local test_name="$1"
  printf "Running test: %s\n" "$test_name"
  "$test_name"
}

test_run_bootstrap_preflight_fails_without_workflow_file() {
  local output

  ensure_git_repository() {
    return 0
  }

  ensure_workflow_file_present() {
    error "Missing required workflow file: .github/workflows/client-deploy.yml"
  }

  output="$(
    (
      run_bootstrap_preflight
    ) 2>&1
  )" || true

  case "$output" in
    *"Missing required workflow file: .github/workflows/client-deploy.yml"* ) ;;
    * )
      fail "run_bootstrap_preflight should fail when the client workflow file is missing"
      ;;
  esac

  pass "run_bootstrap_preflight rejects missing workflow file"
}

test_run_bootstrap_preflight_warns_on_dirty_worktree() {
  local output

  ensure_git_repository() {
    set_preflight_status PREFLIGHT_GIT_REPOSITORY_STATUS "ok"
    return 0
  }

  ensure_workflow_file_present() {
    set_preflight_status PREFLIGHT_WORKFLOW_FILE_STATUS "ok"
    return 0
  }

  ensure_origin_remote_notice() {
    set_preflight_status PREFLIGHT_ORIGIN_REMOTE_STATUS "ok"
    return 0
  }

  working_tree_has_changes() {
    return 0
  }

  output="$(
    run_bootstrap_preflight 2>&1
  )"

  case "$output" in
    *"Git working tree has local changes."* ) ;;
    * )
      fail "run_bootstrap_preflight should warn when the worktree is dirty"
      ;;
  esac

  case "$output" in
    *"  - worktree: dirty"* ) ;;
    * )
      fail "run_bootstrap_preflight should summarize a dirty worktree dynamically"
      ;;
  esac

  pass "run_bootstrap_preflight warns on dirty worktree"
}

test_run_bootstrap_preflight_prints_secret_summary() {
  local output

  ensure_git_repository() {
    set_preflight_status PREFLIGHT_GIT_REPOSITORY_STATUS "ok"
    return 0
  }

  ensure_workflow_file_present() {
    set_preflight_status PREFLIGHT_WORKFLOW_FILE_STATUS "ok"
    return 0
  }

  ensure_origin_remote_notice() {
    set_preflight_status PREFLIGHT_ORIGIN_REMOTE_STATUS "ok"
    return 0
  }

  working_tree_has_changes() {
    return 1
  }

  output="$(
    run_bootstrap_preflight 2>&1
  )"

  case "$output" in
    *"runtime secrets prompted later: workflow-defined secrets"* ) ;;
    * )
      fail "run_bootstrap_preflight should print the runtime secret summary"
      ;;
  esac

  case "$output" in
    *"  - git repository: ok"* ) ;;
    * )
      fail "run_bootstrap_preflight should summarize git repository status dynamically"
      ;;
  esac

  case "$output" in
    *"  - client workflow file: ok"* ) ;;
    * )
      fail "run_bootstrap_preflight should summarize workflow file status dynamically"
      ;;
  esac

  case "$output" in
    *"  - worktree: clean"* ) ;;
    * )
      fail "run_bootstrap_preflight should summarize a clean worktree dynamically"
      ;;
  esac

  pass "run_bootstrap_preflight prints runtime secret summary"
}

test_run_bootstrap_preflight_summarizes_missing_origin_remote() {
  local output

  ensure_git_repository() {
    set_preflight_status PREFLIGHT_GIT_REPOSITORY_STATUS "ok"
    return 0
  }

  ensure_workflow_file_present() {
    set_preflight_status PREFLIGHT_WORKFLOW_FILE_STATUS "ok"
    return 0
  }

  ensure_origin_remote_notice() {
    set_preflight_status PREFLIGHT_ORIGIN_REMOTE_STATUS "missing"
    warn "Git remote origin is not configured yet. Bootstrap will add it after GitHub repo setup."
  }

  working_tree_has_changes() {
    return 1
  }

  output="$(
    run_bootstrap_preflight 2>&1
  )"

  case "$output" in
    *"  - origin remote: missing"* ) ;;
    * )
      fail "run_bootstrap_preflight should summarize a missing origin remote dynamically"
      ;;
  esac

  pass "run_bootstrap_preflight summarizes missing origin remote"
}

run_test test_run_bootstrap_preflight_fails_without_workflow_file
run_test test_run_bootstrap_preflight_warns_on_dirty_worktree
run_test test_run_bootstrap_preflight_prints_secret_summary
run_test test_run_bootstrap_preflight_summarizes_missing_origin_remote
