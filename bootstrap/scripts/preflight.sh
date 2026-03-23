#!/usr/bin/env bash
# Performs local preflight checks before bootstrap touches GitHub or Google Cloud.

PREFLIGHT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v info >/dev/null 2>&1; then
  source "$PREFLIGHT_SCRIPT_DIR/user-prompts.sh"
fi

reset_preflight_state() {
  PREFLIGHT_GIT_REPOSITORY_STATUS="pending"
  PREFLIGHT_WORKFLOW_FILE_STATUS="pending"
  PREFLIGHT_ORIGIN_REMOTE_STATUS="pending"
  PREFLIGHT_WORKTREE_STATUS="pending"
}

set_preflight_status() {
  local key="$1"
  local value="$2"
  printf -v "$key" '%s' "$value"
}

ensure_git_repository() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    set_preflight_status PREFLIGHT_GIT_REPOSITORY_STATUS "failed"
    error "Bootstrap must be run from inside a git repository"
  }

  set_preflight_status PREFLIGHT_GIT_REPOSITORY_STATUS "ok"
}

ensure_origin_remote_notice() {
  if git remote get-url origin >/dev/null 2>&1; then
    set_preflight_status PREFLIGHT_ORIGIN_REMOTE_STATUS "ok"
    info "Git remote origin detected"
  else
    set_preflight_status PREFLIGHT_ORIGIN_REMOTE_STATUS "missing"
    warn "Git remote origin is not configured yet. Bootstrap will add it after GitHub repo setup."
  fi
}

ensure_workflow_file_present() {
  [[ -f .github/workflows/client-deploy.yml ]] || {
    set_preflight_status PREFLIGHT_WORKFLOW_FILE_STATUS "failed"
    error "Missing required workflow file: .github/workflows/client-deploy.yml"
  }

  set_preflight_status PREFLIGHT_WORKFLOW_FILE_STATUS "ok"
}

working_tree_has_changes() {
  ! git diff --quiet || ! git diff --cached --quiet
}

warn_on_dirty_worktree() {
  if working_tree_has_changes; then
    set_preflight_status PREFLIGHT_WORKTREE_STATUS "dirty"
    warn "Git working tree has local changes."
    warn "If bootstrap needs to push origin/main for the first workflow run, it will stop until those changes are committed or stashed."
  else
    set_preflight_status PREFLIGHT_WORKTREE_STATUS "clean"
  fi
}

print_bootstrap_prerequisite_summary() {
  info "Bootstrap preflight checks:"
  printf "  - git repository: %s\n" "$PREFLIGHT_GIT_REPOSITORY_STATUS"
  printf "  - client workflow file: %s\n" "$PREFLIGHT_WORKFLOW_FILE_STATUS"
  printf "  - origin remote: %s\n" "$PREFLIGHT_ORIGIN_REMOTE_STATUS"
  printf "  - worktree: %s\n" "$PREFLIGHT_WORKTREE_STATUS"
  printf "  - runtime secrets prompted later: workflow-defined secrets\n"
}

run_bootstrap_preflight() {
  reset_preflight_state
  ensure_git_repository
  ensure_workflow_file_present
  ensure_origin_remote_notice
  warn_on_dirty_worktree
  print_bootstrap_prerequisite_summary
}
