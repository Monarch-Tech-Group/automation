#!/usr/bin/env bash
# Tests the non-interactive bootstrap entrypoint.
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

test_non_interactive_bootstrap_requires_the_core_inputs() {
  local temp_bootstrap output

  temp_bootstrap="$(mktemp -d)"
  cp "$BOOTSTRAP_ROOT/run-e2e.sh" "$temp_bootstrap/run-e2e.sh"
  write_stub_script "$temp_bootstrap/scripts/user-prompts.sh" '
error() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }
'
  chmod +x "$temp_bootstrap/run-e2e.sh"

  output="$(
    (
      cd "$temp_bootstrap" && ./run-e2e.sh
    ) 2>&1
  )" || true

  case "$output" in
    *"Missing required environment variable: GITHUB_REPO_FULL"* ) ;;
    * )
      rm -rf "$temp_bootstrap"
      fail "non-interactive bootstrap should reject a missing repository identifier"
      ;;
  esac

  rm -rf "$temp_bootstrap"
  pass "non-interactive bootstrap rejects a missing repository identifier"
}

test_non_interactive_bootstrap_derives_defaults_from_the_repository_name() {
  local temp_bootstrap output_file

  temp_bootstrap="$(mktemp -d)"
  output_file="$temp_bootstrap/env.out"
  cp "$BOOTSTRAP_ROOT/run-e2e.sh" "$temp_bootstrap/run-e2e.sh"
  write_stub_script "$temp_bootstrap/scripts/user-prompts.sh" '
error() { printf "\n[ERROR] %s\n" "$*" >&2; exit 1; }
'
  write_stub_script "$temp_bootstrap/main.sh" '
printf "GITHUB_OWNER=%s\n" "$GITHUB_OWNER" > "$BOOTSTRAP_TEST_OUTPUT"
printf "REPO_NAME=%s\n" "$REPO_NAME" >> "$BOOTSTRAP_TEST_OUTPUT"
printf "CLIENT_SERVICE_NAME=%s\n" "$CLIENT_SERVICE_NAME" >> "$BOOTSTRAP_TEST_OUTPUT"
'
  chmod +x "$temp_bootstrap/run-e2e.sh" "$temp_bootstrap/main.sh"

  (
    cd "$temp_bootstrap"
    BOOTSTRAP_TEST_OUTPUT="$output_file" \
    GITHUB_REPO_FULL="acme/demo-app" \
    PROJECT_ID="demo-project" \
    VITE_API_BASE_URL="https://example.test" \
    ./run-e2e.sh
  )

  assert_equals $'GITHUB_OWNER=acme\nREPO_NAME=demo-app\nCLIENT_SERVICE_NAME=demo-app' "$(cat "$output_file")" \
    "non-interactive bootstrap derives owner, repository name, and service name from the repository identifier"

  rm -rf "$temp_bootstrap"
}

run_test test_non_interactive_bootstrap_requires_the_core_inputs
run_test test_non_interactive_bootstrap_derives_defaults_from_the_repository_name
