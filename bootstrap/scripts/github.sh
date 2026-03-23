#!/usr/bin/env bash
# Creates a GitHub repo both locally and remotely for first time bootstrapping only.
# This is only run ONCE by whoever creates the initial repo and pipeline
# When run directly, it performs a dry-run interactive walkthrough and prints derived values.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  source "$SCRIPT_DIR/user-prompts.sh"
fi

git_remote_exists() {
  git remote get-url "$1" >/dev/null 2>&1
}

git_remote_url() {
  git remote get-url "$1"
}

parse_github_org_url() {
  local url="$1"
  echo "${url%/}" | awk -F/ '{print $NF}'
}

parse_github_repo_from_remote() {
  local url="$1"
  local repo

  repo="$url"
  repo="${repo#git@github.com:}"
  repo="${repo#https://github.com/}"
  repo="${repo#http://github.com/}"
  repo="${repo%.git}"

  if [[ "$repo" == */* ]]; then
    printf '%s\n' "$repo"
    return 0
  fi

  return 1
}

set_github_repo_parts() {
  GITHUB_OWNER="${GITHUB_REPO_FULL%%/*}"
  REPO_NAME="${GITHUB_REPO_FULL##*/}"
}

github_repo_exists() {
  gh repo view "$1" >/dev/null 2>&1
}

create_github_repo() {
  local repo="$1"
  info "Creating GitHub repo: $repo"
  if [[ "${BOOTSTRAP_DRY_RUN:-0}" == "1" ]]; then
    info "Dry run enabled. Skipping repo creation."
    return 0
  fi
  gh repo create "$repo" --private
}

ensure_repo_remote() {
  if git_remote_exists origin; then
    return 0
  fi

  [[ -n "${GITHUB_REPO_FULL:-}" ]] || error "Cannot configure git remote without GITHUB_REPO_FULL"
  git remote add origin "https://github.com/${GITHUB_REPO_FULL}.git"
}

git_worktree_clean() {
  git diff --quiet && git diff --cached --quiet
}

remote_main_branch_exists() {
  git ls-remote --exit-code --heads origin main >/dev/null 2>&1
}

ensure_repo_ready_for_workflow_dispatch() {
  ensure_repo_remote

  if remote_main_branch_exists; then
    return 0
  fi

  git_worktree_clean || error "Commit or stash local changes before bootstrap can push origin/main for workflow validation"

  info "Pushing current HEAD to origin/main so the workflow exists on GitHub"
  git push -u origin HEAD:main
}

append_manual_test_marker_to_readme() {
  local readme_path="${1:-README.md}"
  local marker_timestamp

  [[ -f "$readme_path" ]] || error "README not found for manual deploy test: $readme_path"
  marker_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '\n[TESTING DEPLOY] %s\n' "$marker_timestamp" >> "$readme_path"
}

commit_manual_test_readme_change() {
  local readme_path="${1:-README.md}"
  local commit_message="${2:-test: trigger deployment validation}"

  git add "$readme_path"
  git commit -m "$commit_message" -- "$readme_path"
}

push_manual_test_commit() {
  ensure_repo_remote
  git push origin HEAD:main
}

prompt_for_manual_deploy_test() {
  if ! prompt_yes_no "Trigger one final manual deploy test by changing README.md and pushing origin/main?" "no"; then
    return 0
  fi

  append_manual_test_marker_to_readme "README.md"
  commit_manual_test_readme_change "README.md"
  push_manual_test_commit

  info "Manual deploy test commit pushed. Watch the GitHub Actions run in the repository UI."
}

use_existing_origin_repo() {
  local origin_url

  origin_url="$(git_remote_url origin)"
  GITHUB_REPO_FULL="$(parse_github_repo_from_remote "$origin_url")" \
    || error "Unable to derive owner/repo from origin remote: $origin_url"
  set_github_repo_parts
}

configure_github_repo_details() {
  if [[ -n "${GITHUB_REPO_FULL:-}" ]]; then
    set_github_repo_parts
    return 0
  fi

  if [[ -n "${GITHUB_OWNER:-}" && -n "${REPO_NAME:-}" ]]; then
    GITHUB_REPO_FULL="${GITHUB_OWNER}/${REPO_NAME}"
    return 0
  fi

  if git_remote_exists origin && prompt_yes_no "Use the current repo's origin remote for pipeline setup?" "yes"; then
    use_existing_origin_repo
    return 0
  fi

  if prompt_yes_no "Create GitHub repo?"; then
    GITHUB_ORG_URL="$(prompt_default "GitHub org URL")"
    GITHUB_OWNER="$(parse_github_org_url "$GITHUB_ORG_URL")"

    REPO_NAME="$(prompt_default "Repo name")"
    GITHUB_REPO_FULL="${GITHUB_OWNER}/${REPO_NAME}"

    if github_repo_exists "$GITHUB_REPO_FULL"; then
      error "Repo already exists"
    fi

    create_github_repo "$GITHUB_REPO_FULL"
  else
    GITHUB_REPO_FULL="$(prompt_default "owner/repo")"
    set_github_repo_parts
  fi
}

github_main() {
  BOOTSTRAP_DRY_RUN=1
  configure_github_repo_details
  printf "GitHub owner: %s\n" "$GITHUB_OWNER"
  printf "Repo name: %s\n" "$REPO_NAME"
  printf "Repo full name: %s\n" "$GITHUB_REPO_FULL"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  github_main "$@"
fi
