#!/usr/bin/env bash
# Tests the shared user prompt helpers in bootstrap/scripts/user-prompts.sh
# and prints each test name before execution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"


test_requires_a_project_name() {
  local result

  # First input = blank
  # Second input = valid
  result="$(prompt_required "Enter project name" <<< $'\nmy-project')"

  assert_equals "my-project" "$result" \
    "prompt_required forces user to enter a value before continuing"
}

# -----------------------------------
# Tests: prompt_yes_no
# -----------------------------------

test_prompt_yes_no_returns_true_for_y() {
  if prompt_yes_no "Continue?" "no" <<< "y"; then
    pass "prompt_yes_no returns true for y"
  else
    fail "prompt_yes_no should return true for y"
  fi
}

test_prompt_yes_no_returns_true_for_yes() {
  if prompt_yes_no "Continue?" "no" <<< "yes"; then
    pass "prompt_yes_no returns true for yes"
  else
    fail "prompt_yes_no should return true for yes"
  fi
}

test_prompt_yes_no_returns_false_for_n() {
  if prompt_yes_no "Continue?" "yes" <<< "n"; then
    fail "prompt_yes_no should return false for n"
  else
    pass "prompt_yes_no returns false for n"
  fi
}

test_prompt_yes_no_uses_default_yes_when_blank() {
  if prompt_yes_no "Continue?" "yes" <<< ""; then
    pass "prompt_yes_no uses default yes when blank"
  else
    fail "prompt_yes_no should return true when blank and default is yes"
  fi
}

test_prompt_yes_no_uses_default_no_when_blank() {
  if prompt_yes_no "Continue?" "no" <<< ""; then
    fail "prompt_yes_no should return false when blank and default is no"
  else
    pass "prompt_yes_no uses default no when blank"
  fi
}

test_prompt_yes_no_reasks_until_it_receives_a_valid_answer() {
  local output

  output="$(
    {
      prompt_yes_no "Continue?" "yes" <<< $'maybe\ny'
      printf 'accepted'
    } 2>&1
  )"

  case "$output" in
    *"Please answer y or n."*"accepted"* )
      pass "prompt_yes_no re-asks until it receives a valid answer"
      ;;
    * )
      fail "prompt_yes_no should warn and retry when the reply is neither yes nor no"
      ;;
  esac
}

# -----------------------------------
# Tests: validation helpers
# -----------------------------------

test_sanitize_project_id_lowercases_and_replaces_invalid_chars() {
  local result
  result="$(sanitize_project_id "My Cool_App!")"
  assert_equals "my-cool-app" "$result" "sanitize_project_id normalizes value"
}

test_validate_project_id_format_accepts_valid_id() {
  if validate_project_id_format "my-proj-123"; then
    pass "validate_project_id_format accepts valid id"
  else
    fail "validate_project_id_format should accept valid id"
  fi
}

test_validate_project_id_format_rejects_invalid_id() {
  if validate_project_id_format "MyProj"; then
    fail "validate_project_id_format should reject invalid id"
  else
    pass "validate_project_id_format rejects invalid id"
  fi
}

test_ensure_gcloud_cli_returns_when_already_installed() {
  command_exists() {
    [[ "$1" == "gcloud" ]]
  }

  prompt_yes_no() {
    fail "prompt_yes_no should not be called when gcloud already exists"
  }

  ensure_gcloud_cli
  pass "ensure_gcloud_cli does nothing when gcloud is already installed"
}

test_ensure_gcloud_cli_accepts_an_installed_binary_that_is_not_yet_on_path() {
  local refreshed=0

  command_exists() {
    if [[ "$1" == "brew" ]]; then
      return 0
    fi
    if [[ "$1" == "gcloud" && "$refreshed" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  refresh_brew_shellenv() {
    refreshed=1
  }

  prompt_yes_no() {
    fail "prompt_yes_no should not be called when gcloud becomes available after shell refresh"
  }

  ensure_gcloud_cli
  pass "ensure_gcloud_cli accepts an installed gcloud binary after refreshing the shell environment"
}

test_ensure_gcloud_cli_installs_with_brew_when_approved() {
  local installed=0

  command_exists() {
    if [[ "$1" == "brew" ]]; then
      return 0
    fi
    if [[ "$1" == "gcloud" && "$installed" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  prompt_yes_no() {
    return 0
  }

  install_gcloud_with_brew() {
    installed=1
  }

  refresh_brew_shellenv() {
    return 0
  }

  ensure_gcloud_cli
  pass "ensure_gcloud_cli installs gcloud with brew when approved"
}

test_ensure_gcloud_cli_installs_brew_then_gcloud_when_needed() {
  local brew_installed=0
  local gcloud_installed=0

  command_exists() {
    if [[ "$1" == "brew" && "$brew_installed" -eq 1 ]]; then
      return 0
    fi
    if [[ "$1" == "gcloud" && "$gcloud_installed" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  prompt_yes_no() {
    return 0
  }

  install_brew() {
    brew_installed=1
  }

  install_gcloud_with_brew() {
    gcloud_installed=1
  }

  refresh_brew_shellenv() {
    return 0
  }

  ensure_gcloud_cli
  pass "ensure_gcloud_cli installs Homebrew and gcloud when both are missing"
}

test_ensure_gcloud_cli_refreshes_the_shell_environment_after_install() {
  local shellenv_refreshed=0
  local installed=0

  command_exists() {
    if [[ "$1" == "brew" ]]; then
      return 0
    fi
    if [[ "$1" == "gcloud" && "$installed" -eq 1 && "$shellenv_refreshed" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  prompt_yes_no() {
    return 0
  }

  install_gcloud_with_brew() {
    installed=1
  }

  refresh_brew_shellenv() {
    shellenv_refreshed=1
  }

  ensure_gcloud_cli
  pass "ensure_gcloud_cli refreshes the shell environment after installing gcloud"
}

test_ensure_gh_cli_returns_when_already_installed() {
  command_exists() {
    [[ "$1" == "gh" ]]
  }

  prompt_yes_no() {
    fail "prompt_yes_no should not be called when gh already exists"
  }

  ensure_gh_cli
  pass "ensure_gh_cli does nothing when gh is already installed"
}

test_ensure_gh_cli_installs_with_brew_when_approved() {
  local installed=0
  local shellenv_refreshed=0

  command_exists() {
    if [[ "$1" == "brew" ]]; then
      return 0
    fi
    if [[ "$1" == "gh" && "$installed" -eq 1 && "$shellenv_refreshed" -eq 1 ]]; then
      return 0
    fi
    return 1
  }

  prompt_yes_no() {
    return 0
  }

  install_gh_with_brew() {
    return 0
  }

  refresh_brew_shellenv() {
    installed=1
    shellenv_refreshed=1
  }

  ensure_gh_cli
  pass "ensure_gh_cli installs gh with brew when approved"
}

test_ensure_required_tools_upgrades_homebrew_managed_gh_and_gcloud() {
  local temp_dir gh_marker gcloud_marker

  temp_dir="$(mktemp -d)"
  gh_marker="$temp_dir/gh-upgraded"
  gcloud_marker="$temp_dir/gcloud-upgraded"

  ensure_gcloud_cli() {
    return 0
  }

  ensure_gh_cli() {
    return 0
  }

  command_exists() {
    [[ "$1" == "brew" || "$1" == "gh" ]]
  }

  brew_formula_is_installed() {
    [[ "$1" == "gh" ]]
  }

  brew_cask_is_installed() {
    [[ "$1" == "gcloud-cli" ]]
  }

  upgrade_brew_formula() {
    : > "$gh_marker"
  }

  upgrade_brew_cask() {
    : > "$gcloud_marker"
  }

  refresh_brew_shellenv() {
    return 0
  }

  ensure_gcloud_on_path() {
    return 0
  }

  ensure_required_tools

  assert_equals "1" "$([[ -f "$gh_marker" ]] && printf '1' || printf '0')" \
    "ensure_required_tools upgrades Homebrew-managed gh before bootstrap continues"
  assert_equals "1" "$([[ -f "$gcloud_marker" ]] && printf '1' || printf '0')" \
    "ensure_required_tools upgrades Homebrew-managed gcloud before bootstrap continues"

  rm -rf "$temp_dir"
}

test_ensure_required_tools_continues_when_homebrew_cannot_confirm_the_gcloud_cask_installation() {
  local temp_dir gh_marker

  temp_dir="$(mktemp -d)"
  gh_marker="$temp_dir/gh-upgraded"

  ensure_gcloud_cli() {
    return 0
  }

  ensure_gh_cli() {
    return 0
  }

  command_exists() {
    [[ "$1" == "brew" || "$1" == "gh" ]]
  }

  brew_formula_is_installed() {
    [[ "$1" == "gh" ]]
  }

  detect_installed_gcloud_cask() {
    printf 'gcloud-cli'
  }

  upgrade_brew_formula() {
    : > "$gh_marker"
  }

  upgrade_brew_cask() {
    printf "Error: Cask 'gcloud-cli' is not installed.\n" >&2
    return 1
  }

  refresh_brew_shellenv() {
    return 0
  }

  ensure_gcloud_on_path() {
    return 0
  }

  ensure_required_tools

  assert_equals "1" "$([[ -f "$gh_marker" ]] && printf '1' || printf '0')" \
    "ensure_required_tools still upgrades gh when Homebrew cannot confirm the gcloud cask installation"

  rm -rf "$temp_dir"
}

test_ensure_gcloud_cli_prints_brew_instructions_when_brew_missing_and_declined() {
  local output

  source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"

  command_exists() {
    return 1
  }

  find_gcloud_binary() {
    return 1
  }

  prompt_yes_no() {
    return 1
  }

  output="$(
    (
      ensure_gcloud_cli
    ) 2>&1
  )" || true

  case "$output" in
    *'Homebrew install script:'* ) ;;
    * )
      fail "ensure_gcloud_cli should print Homebrew install instructions when brew is unavailable"
      ;;
  esac

  case "$output" in
    *'raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'* ) ;;
    * )
      fail "ensure_gcloud_cli should print the Homebrew install script when brew is unavailable"
      ;;
  esac

  pass "ensure_gcloud_cli prints Homebrew instructions when it cannot auto-install"
}

test_ensure_gcloud_cli_prints_gcloud_instructions_when_install_declined() {
  local output

  source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"

  command_exists() {
    [[ "$1" == "brew" ]]
  }

  find_gcloud_binary() {
    return 1
  }

  prompt_yes_no() {
    return 1
  }

  output="$(
    (
      ensure_gcloud_cli
    ) 2>&1
  )" || true

  case "$output" in
    *"brew install --cask gcloud-cli"* ) ;;
    * )
      fail "ensure_gcloud_cli should print gcloud install instructions when gcloud install is declined"
      ;;
  esac

  case "$output" in
    *"curl https://sdk.cloud.google.com | bash"* ) ;;
    * )
      fail "ensure_gcloud_cli should print the official gcloud install script when gcloud install is declined"
      ;;
  esac

  pass "ensure_gcloud_cli prints gcloud instructions when gcloud install is declined"
}

test_ensure_gcloud_cli_shows_the_brew_error_output_when_install_fails() {
  local output

  source "$BOOTSTRAP_ROOT/scripts/user-prompts.sh"

  command_exists() {
    [[ "$1" == "brew" ]]
  }

  find_gcloud_binary() {
    return 1
  }

  prompt_yes_no() {
    return 0
  }

  install_gcloud_with_brew() {
    printf 'brew install failed for a concrete reason\n' >&2
    return 1
  }

  output="$(
    (
      ensure_gcloud_cli
    ) 2>&1
  )" || true

  case "$output" in
    *"brew install failed for a concrete reason"* ) ;;
    * )
      fail "ensure_gcloud_cli should surface the underlying Homebrew install error"
      ;;
  esac

  pass "ensure_gcloud_cli surfaces the underlying Homebrew install error"
}

test_gcloud_installation_prefers_the_current_python3_binary() {
  local received_python=""

  command_exists() {
    [[ "$1" == "python3" ]]
  }

  command() {
    if [[ "$1" == "-v" && "$2" == "python3" ]]; then
      printf '/opt/homebrew/bin/python3\n'
      return 0
    fi

    builtin command "$@"
  }

  brew() {
    received_python="${CLOUDSDK_PYTHON:-}"
  }

  install_gcloud_with_brew() {
    local gcloud_python

    gcloud_python="$(select_gcloud_python || true)"
    if [[ -n "$gcloud_python" ]]; then
      CLOUDSDK_PYTHON="$gcloud_python" brew install --cask google-cloud-sdk
      CLOUDSDK_PYTHON="$gcloud_python" brew install --cask gcloud-cli
      return 0
    fi

    brew install --cask gcloud-cli
  }

  install_gcloud_with_brew

  assert_equals "/opt/homebrew/bin/python3" "$received_python" \
    "gcloud installation uses the current python3 binary when one is available"
}

test_ensure_gh_auth_prints_instructions_when_not_authenticated() {
  local output

  gh() {
    return 1
  }

  prompt_yes_no() {
    return 1
  }

  output="$(
    (
      ensure_gh_auth
    ) 2>&1
  )" || true

  case "$output" in
    *"gh auth login -h github.com"* ) ;;
    * )
      fail "ensure_gh_auth should print the gh auth login command"
      ;;
  esac

  pass "ensure_gh_auth prints login instructions when gh is not authenticated"
}

test_ensure_gh_auth_runs_login_when_approved() {
  local authenticated=0
  local login_attempted=0

  gh() {
    if [[ "$1" == "auth" && "$2" == "status" ]]; then
      [[ "$authenticated" -eq 1 ]]
      return
    fi

    return 1
  }

  prompt_yes_no() {
    return 0
  }

  run_gh_auth_login() {
    login_attempted=1
    authenticated=1
  }

  ensure_gh_auth

  assert_equals "1" "$login_attempted" \
    "ensure_gh_auth runs GitHub CLI login when the user approves it"
}

test_ensure_gcloud_auth_prints_instructions_when_not_authenticated() {
  local output

  gcloud() {
    if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "account" ]]; then
      printf "(unset)\n"
      return 0
    fi

    return 1
  }

  prompt_yes_no() {
    return 1
  }

  output="$(
    (
      ensure_gcloud_auth
    ) 2>&1
  )" || true

  case "$output" in
    *"gcloud auth login"* ) ;;
    * )
      fail "ensure_gcloud_auth should print the gcloud auth login command"
      ;;
  esac

  pass "ensure_gcloud_auth prints login instructions when gcloud is not authenticated"
}

test_ensure_gcloud_auth_accepts_an_active_configured_account() {
  gcloud() {
    if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "account" ]]; then
      printf "dev@example.com\n"
      return 0
    fi

    return 1
  }

  ensure_gcloud_auth
  pass "ensure_gcloud_auth accepts an active configured account"
}

test_ensure_gcloud_auth_runs_login_when_approved() {
  local authenticated=0
  local login_attempted=0

  gcloud() {
    if [[ "$1" == "config" && "$2" == "get-value" && "$3" == "account" ]]; then
      if [[ "$authenticated" -eq 1 ]]; then
        printf "dev@example.com\n"
      else
        printf "(unset)\n"
      fi
      return 0
    fi

    return 1
  }

  prompt_yes_no() {
    return 0
  }

  run_gcloud_auth_login() {
    login_attempted=1
    authenticated=1
  }

  ensure_gcloud_auth

  assert_equals "1" "$login_attempted" \
    "ensure_gcloud_auth runs Google Cloud login when the user approves it"
}

# -----------------------------------
# Runner
# -----------------------------------

run_all_tests() {
  run_test test_requires_a_project_name
  run_test test_prompt_yes_no_returns_true_for_y
  run_test test_prompt_yes_no_returns_true_for_yes
  run_test test_prompt_yes_no_returns_false_for_n
  run_test test_prompt_yes_no_uses_default_yes_when_blank
  run_test test_prompt_yes_no_uses_default_no_when_blank
  run_test test_prompt_yes_no_reasks_until_it_receives_a_valid_answer
  run_test test_sanitize_project_id_lowercases_and_replaces_invalid_chars
  run_test test_validate_project_id_format_accepts_valid_id
  run_test test_validate_project_id_format_rejects_invalid_id
  run_test test_ensure_gcloud_cli_returns_when_already_installed
  run_test test_ensure_gcloud_cli_accepts_an_installed_binary_that_is_not_yet_on_path
  run_test test_ensure_gcloud_cli_installs_with_brew_when_approved
  run_test test_ensure_gcloud_cli_installs_brew_then_gcloud_when_needed
  run_test test_ensure_gcloud_cli_refreshes_the_shell_environment_after_install
  run_test test_ensure_gh_cli_returns_when_already_installed
  run_test test_ensure_gh_cli_installs_with_brew_when_approved
  run_test test_ensure_required_tools_upgrades_homebrew_managed_gh_and_gcloud
  run_test test_ensure_required_tools_continues_when_homebrew_cannot_confirm_the_gcloud_cask_installation
  run_test test_ensure_gcloud_cli_prints_brew_instructions_when_brew_missing_and_declined
  run_test test_ensure_gcloud_cli_prints_gcloud_instructions_when_install_declined
  run_test test_ensure_gcloud_cli_shows_the_brew_error_output_when_install_fails
  run_test test_gcloud_installation_prefers_the_current_python3_binary
  run_test test_ensure_gh_auth_prints_instructions_when_not_authenticated
  run_test test_ensure_gh_auth_runs_login_when_approved
  run_test test_ensure_gcloud_auth_prints_instructions_when_not_authenticated
  run_test test_ensure_gcloud_auth_accepts_an_active_configured_account
  run_test test_ensure_gcloud_auth_runs_login_when_approved
}

# -----------------------------------
# Helpers (LAST)
# -----------------------------------

run_test() {
  local test_name="$1"
  printf "Running test: %s\n" "$test_name"
  "$test_name"
}

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

# -----------------------------------
# Execute
# -----------------------------------

run_all_tests
