#!/usr/bin/env bash
# Tests non-interactive GitHub bootstrap configuration helpers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"
source "$BOOTSTRAP_ROOT/scripts/github.sh"

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

test_configure_github_repo_details_uses_repo_full_env_without_prompting() {
  GITHUB_REPO_FULL="acme/demo"
  unset GITHUB_OWNER
  unset REPO_NAME

  configure_github_repo_details

  assert_equals "acme" "$GITHUB_OWNER" \
    "configure_github_repo_details derives owner from GITHUB_REPO_FULL"
  assert_equals "demo" "$REPO_NAME" \
    "configure_github_repo_details derives repo name from GITHUB_REPO_FULL"
}

test_configure_github_repo_details_uses_owner_and_repo_env_without_prompting() {
  unset GITHUB_REPO_FULL
  GITHUB_OWNER="acme"
  REPO_NAME="demo"

  configure_github_repo_details

  assert_equals "acme/demo" "$GITHUB_REPO_FULL" \
    "configure_github_repo_details composes GITHUB_REPO_FULL from env"
}

test_configure_github_repo_details_uses_the_existing_origin_remote_when_selected() {
  unset GITHUB_REPO_FULL GITHUB_OWNER REPO_NAME

  git_remote_exists() {
    [[ "$1" == "origin" ]]
  }

  git_remote_url() {
    printf 'git@github.com:acme/demo.git\n'
  }

  prompt_yes_no() {
    return 0
  }

  configure_github_repo_details

  assert_equals "acme/demo" "$GITHUB_REPO_FULL" \
    "configure_github_repo_details derives owner and repo from the current origin remote"
  assert_equals "acme" "$GITHUB_OWNER" \
    "configure_github_repo_details derives the owner from the current origin remote"
  assert_equals "demo" "$REPO_NAME" \
    "configure_github_repo_details derives the repository name from the current origin remote"
}

test_parse_github_repo_from_remote_accepts_https_and_ssh_formats() {
  assert_equals "acme/demo" "$(parse_github_repo_from_remote "https://github.com/acme/demo.git")" \
    "parse_github_repo_from_remote accepts the https remote format"
  assert_equals "acme/demo" "$(parse_github_repo_from_remote "git@github.com:acme/demo.git")" \
    "parse_github_repo_from_remote accepts the ssh remote format"
}

test_prompt_for_manual_deploy_test_pushes_a_readme_commit_when_selected() {
  local temp_dir readme_path log_file readme_contents

  temp_dir="$(mktemp -d)"
  readme_path="$temp_dir/README.md"
  log_file="$temp_dir/manual-test.log"
  printf '# Demo\n' > "$readme_path"

  prompt_yes_no() {
    return 0
  }

  commit_manual_test_readme_change() {
    printf 'commit:%s|' "$1" >> "$log_file"
  }

  push_manual_test_commit() {
    printf 'push|' >> "$log_file"
  }

  prompt_for_manual_deploy_test() {
    if ! prompt_yes_no "Trigger one final manual deploy test by changing README.md and pushing origin/main?" "no"; then
      return 0
    fi

    append_manual_test_marker_to_readme "$readme_path"
    commit_manual_test_readme_change "$readme_path"
    push_manual_test_commit
  }

  prompt_for_manual_deploy_test

  readme_contents="$(cat "$readme_path")"
  case "$readme_contents" in
    *"[TESTING DEPLOY]"* ) ;;
    * )
      fail "prompt_for_manual_deploy_test should append the testing deploy marker to README.md"
      ;;
  esac

  assert_equals "commit:$readme_path|push|" "$(cat "$log_file")" \
    "prompt_for_manual_deploy_test appends the marker, commits README.md, and pushes when selected"

  rm -rf "$temp_dir"
}

test_prompt_for_manual_deploy_test_skips_the_readme_commit_when_declined() {
  local temp_dir readme_path log_file readme_contents

  temp_dir="$(mktemp -d)"
  readme_path="$temp_dir/README.md"
  log_file="$temp_dir/manual-test.log"
  printf '# Demo\n' > "$readme_path"

  prompt_yes_no() {
    return 1
  }

  commit_manual_test_readme_change() {
    printf 'commit|' >> "$log_file"
  }

  push_manual_test_commit() {
    printf 'push|' >> "$log_file"
  }

  prompt_for_manual_deploy_test() {
    if ! prompt_yes_no "Trigger one final manual deploy test by changing README.md and pushing origin/main?" "no"; then
      return 0
    fi

    append_manual_test_marker_to_readme "$readme_path"
    commit_manual_test_readme_change "$readme_path"
    push_manual_test_commit
  }

  prompt_for_manual_deploy_test
  readme_contents="$(cat "$readme_path")"

  assert_equals "# Demo" "$readme_contents" \
    "prompt_for_manual_deploy_test leaves README.md unchanged when declined"
  assert_equals "" "$(cat "$log_file" 2>/dev/null || true)" \
    "prompt_for_manual_deploy_test skips append, commit, and push when declined"

  rm -rf "$temp_dir"
}

run_test test_configure_github_repo_details_uses_repo_full_env_without_prompting
run_test test_configure_github_repo_details_uses_owner_and_repo_env_without_prompting
run_test test_configure_github_repo_details_uses_the_existing_origin_remote_when_selected
run_test test_parse_github_repo_from_remote_accepts_https_and_ssh_formats
run_test test_prompt_for_manual_deploy_test_pushes_a_readme_commit_when_selected
run_test test_prompt_for_manual_deploy_test_skips_the_readme_commit_when_declined
