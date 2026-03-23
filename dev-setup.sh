#!/bin/zsh
#
# macOS developer machine bootstrap script
#
# Used to quickly install a bunch of things you will need on a new Monarch Development machine.
#
# HOW TO RUN:
# 1. Save this file from github as: setup.sh to your file system somewhere
# 2. Make it executable:
#      chmod +x dev-setup.sh
# 3. Cd to the folder that contains it then tun it:
#      ./dev-setup.sh
#
# ALTERNATIVE:
# You can also run it explicitly with zsh:
#      zsh dev-setup.sh
#
# NOTES:
# - This script installs Homebrew if it is missing.
# - Some installs may prompt for your macOS password.
# - If Homebrew was just installed and not yet on PATH, the script will stop.
#   In that case, open a new Terminal window and run ./setup.sh again.
# - Restart your terminal after the script finishes so new CLI tools are available.
#
set -euo pipefail

echo_step() {
  echo
  echo "==> $1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

brew_formula_installed() {
  brew list --formula "$1" >/dev/null 2>&1
}

brew_cask_installed() {
  brew list --cask "$1" >/dev/null 2>&1
}

install_formula() {
  local formula="$1"
  if brew_formula_installed "$formula"; then
    echo "Already installed: $formula"
  else
    brew install "$formula"
  fi
}

install_cask() {
  local cask="$1"
  if brew_cask_installed "$cask"; then
    echo "Already installed: $cask"
  else
    brew install --cask "$cask" || echo "Skipped: $cask (may already be installed outside Homebrew)"
  fi
}

echo_step "Enable showing hidden files in macOS Finder"
defaults write com.apple.finder AppleShowAllFiles -bool true
killall Finder >/dev/null 2>&1 || true

echo_step "Install Homebrew if needed"
if ! have_cmd brew; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  else
    echo "Homebrew installed, but brew is not on PATH yet."
    echo "Open a new terminal and run this script again."
    exit 1
  fi
fi

echo_step "Update Homebrew"
brew update

echo_step "Install runtimes and CLI tools"
install_formula node
install_formula pnpm
install_formula yarn
install_formula git
install_formula wget

echo_step "Install oh-my-zsh if needed"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  echo "Already installed: oh-my-zsh"
else
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

echo_step "Install browsers"
install_cask google-chrome
install_cask brave-browser

echo_step "Install communication tools"
install_cask zoom
install_cask slack

echo_step "Install dev tools"
install_cask postman
install_cask tuple
install_cask docker-desktop
install_formula git
install_cask sublime-text
install_cask jetbrains-toolbox
install_cask visual-studio-code

echo_step "Install utilities"
install_cask iterm2
install_cask rectangle
install_cask 1password
install_cask notion

echo_step "Install Claude Code"
if have_cmd claude; then
  echo "Already installed: claude"
else
  curl -fsSL https://claude.ai/install.sh | bash
fi

echo_step "Install Codex"
if have_cmd codex; then
  echo "Already installed: codex"
else
  brew install --cask codex
fi

echo_step "Install ChatGPT desktop app"
install_cask chatgpt

echo_step "Done"
echo "Restart your terminal before using newly installed CLIs."
