#!/usr/bin/env bash
# Tests the shell test runner.
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

run_test() {
  local test_name="$1"
  printf "Running test: %s\n" "$test_name"
  "$test_name"
}

test_shell_test_runner_reports_successful_files() {
  local temp_bootstrap output

  temp_bootstrap="$(mktemp -d)"
  mkdir -p "$temp_bootstrap/tests"
  cp "$BOOTSTRAP_ROOT/run-tests.sh" "$temp_bootstrap/run-tests.sh"
  cat > "$temp_bootstrap/tests/passing.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$temp_bootstrap/run-tests.sh" "$temp_bootstrap/tests/passing.sh"

  output="$(
    cd "$temp_bootstrap" && ./run-tests.sh
  )"

  case "$output" in
    *"Files: 1 passed, 0 failed, 1 total"* ) ;;
    * )
      rm -rf "$temp_bootstrap"
      fail "shell test runner should summarize passing test files"
      ;;
  esac

  rm -rf "$temp_bootstrap"
  pass "shell test runner summarizes passing test files"
}

test_shell_test_runner_reports_failing_files() {
  local temp_bootstrap output

  temp_bootstrap="$(mktemp -d)"
  mkdir -p "$temp_bootstrap/tests"
  cp "$BOOTSTRAP_ROOT/run-tests.sh" "$temp_bootstrap/run-tests.sh"
  cat > "$temp_bootstrap/tests/failing.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$temp_bootstrap/run-tests.sh" "$temp_bootstrap/tests/failing.sh"

  output="$(
    (
      cd "$temp_bootstrap" && ./run-tests.sh
    ) 2>&1
  )" || true

  case "$output" in
    *"Files: 0 passed, 1 failed, 1 total"* ) ;;
    * )
      rm -rf "$temp_bootstrap"
      fail "shell test runner should summarize failing test files"
      ;;
  esac

  rm -rf "$temp_bootstrap"
  pass "shell test runner summarizes failing test files"
}

run_test test_shell_test_runner_reports_successful_files
run_test test_shell_test_runner_reports_failing_files
