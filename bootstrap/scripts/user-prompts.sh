#!/usr/bin/env bash
# Walks you through the bootstrapping by asking you for a project/repo name to base it on.
# When run directly, it prompts for and echoes a project name.

info()  { printf "\n[INFO] %s\n" "$*"; }
warn()  { printf "\n[WARN] %s\n" "$*" >&2; }
error() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  command_exists "$1" || error "Required command not found: $1"
}

prompt_required() {
  local prompt="$1"
  local value=""

  while true; do
    read -r -p "$prompt: " value

    if [[ -n "$value" ]]; then
      printf "%s" "$value"
      return 0
    fi

    warn "Value cannot be empty. Please enter a value."
  done
}

print_gcloud_install_instructions() {
  cat <<'EOF' >&2
Install the Google Cloud CLI in another terminal, then re-run bootstrap.

Homebrew:
  brew install --cask gcloud-cli

Official install script:
  curl https://sdk.cloud.google.com | bash
EOF
}

print_gh_install_instructions() {
  cat <<'EOF' >&2
Install the GitHub CLI in another terminal, then re-run bootstrap.

Homebrew:
  brew install gh
EOF
}

print_brew_install_instructions() {
  cat <<'EOF' >&2
Homebrew is required to auto-install the Google Cloud CLI.
Install Homebrew in another terminal, then re-run bootstrap.

Homebrew install script:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
EOF
}

install_brew() {
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

refresh_brew_shellenv() {
  if command_exists brew; then
    eval "$(brew shellenv)"
  fi
}

select_gcloud_python() {
  if command_exists python3; then
    command -v python3
    return 0
  fi

  if command_exists python; then
    command -v python
    return 0
  fi

  return 1
}

install_gcloud_with_brew() {
  local gcloud_python

  gcloud_python="$(select_gcloud_python || true)"
  if [[ -n "$gcloud_python" ]]; then
    CLOUDSDK_PYTHON="$gcloud_python" brew install --cask gcloud-cli
    return 0
  fi

  brew install --cask gcloud-cli
}

install_gh_with_brew() {
  brew install gh
}

find_gcloud_binary() {
  local candidate

  for candidate in \
    "/opt/homebrew/bin/gcloud" \
    "/usr/local/bin/gcloud" \
    "/opt/homebrew/share/google-cloud-sdk/bin/gcloud" \
    "/usr/local/share/google-cloud-sdk/bin/gcloud"
  do
    if [[ -x "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_gcloud_on_path() {
  local gcloud_bin

  if command_exists gcloud; then
    return 0
  fi

  refresh_brew_shellenv

  if command_exists gcloud; then
    return 0
  fi

  gcloud_bin="$(find_gcloud_binary || true)"
  if [[ -n "$gcloud_bin" ]]; then
    export PATH="$(dirname "$gcloud_bin"):$PATH"
    return 0
  fi

  return 1
}

ensure_gcloud_cli() {
  local install_output

  if ensure_gcloud_on_path; then
    return 0
  fi

  warn "Google Cloud CLI (gcloud) is not installed."

  if ! command_exists brew; then
    warn "Homebrew is not installed."

    if prompt_yes_no "Install Homebrew now?" "yes"; then
      install_brew || {
        print_brew_install_instructions
        error "Automatic Homebrew installation failed"
      }

      refresh_brew_shellenv
    else
      print_brew_install_instructions
      error "Homebrew is required to auto-install gcloud"
    fi
  fi

  if prompt_yes_no "Install Google Cloud CLI with Homebrew now?" "yes"; then
    install_output="$(
      install_gcloud_with_brew 2>&1
    )" || {
      warn "Homebrew reported an error while installing gcloud:"
      printf '%s\n' "$install_output" >&2
      print_gcloud_install_instructions
      error "Automatic gcloud installation failed"
    }

    ensure_gcloud_on_path && return 0

    warn "Homebrew installation finished, but gcloud is still not available on PATH."
    print_gcloud_install_instructions
    error "gcloud was not found after Homebrew installation"
  fi

  print_gcloud_install_instructions
  error "gcloud is required before running bootstrap"
}

ensure_gh_cli() {
  local install_output

  if command_exists gh; then
    return 0
  fi

  warn "GitHub CLI (gh) is not installed."

  if ! command_exists brew; then
    warn "Homebrew is not installed."

    if prompt_yes_no "Install Homebrew now?" "yes"; then
      install_brew || {
        print_brew_install_instructions
        error "Automatic Homebrew installation failed"
      }

      refresh_brew_shellenv
    else
      print_brew_install_instructions
      error "Homebrew is required to auto-install gh"
    fi
  fi

  if prompt_yes_no "Install GitHub CLI with Homebrew now?" "yes"; then
    install_output="$(
      install_gh_with_brew 2>&1
    )" || {
      warn "Homebrew reported an error while installing gh:"
      printf '%s\n' "$install_output" >&2
      print_gh_install_instructions
      error "Automatic gh installation failed"
    }

    refresh_brew_shellenv
    command_exists gh && return 0

    warn "Homebrew installation finished, but gh is still not available on PATH."
    print_gh_install_instructions
    error "gh was not found after Homebrew installation"
  fi

  print_gh_install_instructions
  error "gh is required before running bootstrap"
}

brew_formula_is_installed() {
  brew list --formula --versions "$1" >/dev/null 2>&1
}

brew_cask_is_installed() {
  brew list --cask --versions "$1" >/dev/null 2>&1
}

detect_installed_gcloud_cask() {
  if brew_cask_is_installed gcloud-cli; then
    printf 'gcloud-cli'
    return 0
  fi

  if brew_cask_is_installed google-cloud-sdk; then
    printf 'google-cloud-sdk'
    return 0
  fi

  return 1
}

upgrade_brew_formula() {
  brew upgrade "$1"
}

upgrade_brew_cask() {
  brew upgrade --cask "$1"
}

ensure_latest_homebrew_managed_tools() {
  local upgrade_output
  local gcloud_cask=""

  command_exists brew || return 0

  if brew_formula_is_installed gh; then
    info "Ensuring GitHub CLI is up to date..."
    upgrade_output="$(
      upgrade_brew_formula gh 2>&1
    )" || {
      warn "Homebrew reported an error while upgrading gh:"
      printf '%s\n' "$upgrade_output" >&2
      error "Unable to upgrade gh to the latest version"
    }
  fi

  gcloud_cask="$(detect_installed_gcloud_cask || true)"
  if [[ -n "$gcloud_cask" ]]; then
    info "Ensuring Google Cloud CLI is up to date..."
    upgrade_output="$(
      upgrade_brew_cask "$gcloud_cask" 2>&1
    )" || {
      if printf '%s\n' "$upgrade_output" | rg -q "is not installed"; then
        warn "Homebrew could not confirm ${gcloud_cask} is installed. Continuing with the gcloud already on PATH."
        refresh_brew_shellenv
        ensure_gcloud_on_path || true
        return 0
      fi

      warn "Homebrew reported an error while upgrading ${gcloud_cask}:"
      printf '%s\n' "$upgrade_output" >&2
      error "Unable to upgrade ${gcloud_cask} to the latest version"
    }
  fi

  refresh_brew_shellenv
  ensure_gcloud_on_path || true
}

ensure_required_tools() {
  ensure_gcloud_cli
  ensure_gh_cli
  ensure_latest_homebrew_managed_tools
  require_cmd gh
}

print_gh_auth_instructions() {
  cat <<'EOF' >&2
GitHub CLI authentication is required before running bootstrap.

Run this in another terminal:
  gh auth login -h github.com
EOF
}

run_gh_auth_login() {
  gh auth login -h github.com
}

run_gcloud_auth_login() {
  gcloud auth login
}

print_gcloud_auth_instructions() {
  cat <<'EOF' >&2
Google Cloud authentication is required before running bootstrap.

Run this in another terminal:
  gcloud auth login

If you need to select a project afterward:
  gcloud config set project YOUR_PROJECT_ID
EOF
}

ensure_gh_auth() {
  info "Checking gh auth..."
  if gh auth status >/dev/null 2>&1; then
    return 0
  fi

  warn "GitHub CLI is not authenticated."
  if prompt_yes_no "Run GitHub CLI login now?" "yes"; then
    run_gh_auth_login || {
      print_gh_auth_instructions
      error "GitHub CLI authentication failed"
    }

    if gh auth status >/dev/null 2>&1; then
      return 0
    fi
  fi

  print_gh_auth_instructions
  error "Authenticate gh before running bootstrap"
}

ensure_gcloud_auth() {
  local active_account=""

  info "Checking gcloud auth..."
  active_account="$(gcloud config get-value account 2>/dev/null || true)"
  if [[ -n "$active_account" && "$active_account" != "(unset)" ]]; then
    return 0
  fi

  warn "Google Cloud CLI is not authenticated."
  if prompt_yes_no "Run Google Cloud login now?" "yes"; then
    run_gcloud_auth_login || {
      print_gcloud_auth_instructions
      error "Google Cloud authentication failed"
    }

    active_account="$(gcloud config get-value account 2>/dev/null || true)"
    if [[ -n "$active_account" && "$active_account" != "(unset)" ]]; then
      return 0
    fi
  fi

  print_gcloud_auth_instructions
  error "Authenticate gcloud before running bootstrap"
}

ensure_cli_auth() {
  ensure_gcloud_auth
  ensure_gh_auth
}

prompt_default() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    printf "%s" "${value:-$default}"
  else
    read -r -p "$prompt: " value
    printf "%s" "$value"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local reply
  local normalized_reply

  while true; do
    read -r -p "$prompt [y/n]: " reply || return 1
    reply="${reply:-$default}"
    normalized_reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"

    case "$normalized_reply" in
      y|yes)
        return 0
        ;;
      n|no)
        return 1
        ;;
      *)
        warn "Please answer y or n."
        ;;
    esac
  done
}

sanitize_project_id() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g' \
    | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

validate_project_id_format() {
  [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

user_prompts_main() {
  local project_name
  project_name="$(prompt_required "Enter project name")"
  printf "Project name: %s\n" "$project_name"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  user_prompts_main "$@"
fi
