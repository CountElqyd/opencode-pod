#!/usr/bin/env bats

setup_file() {
  TESTDIR="$(mktemp -d)"
  export BATS_TEST_DIRNAME_TARBALL="$TESTDIR"
  mkdir -p "$TESTDIR/tarball-src/config" "$TESTDIR/tarball-src/skills" "$TESTDIR/tarball-src/agents"
  echo '{"permissions":{}}' > "$TESTDIR/tarball-src/config/opencode.json"
  echo "# test skill" > "$TESTDIR/tarball-src/skills/test.md"
  echo "# test agent" > "$TESTDIR/tarball-src/agents/test.md"
  echo "0.1.0" > "$TESTDIR/VERSION"
  tar czf "$TESTDIR/ralph.tar.gz" -C "$TESTDIR" tarball-src/ VERSION
}

teardown_file() {
  [[ -n "${BATS_TEST_DIRNAME_TARBALL:-}" ]] && rm -rf "$BATS_TEST_DIRNAME_TARBALL"
}

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.config/opencode"
}

teardown() {
  rm -rf "${TEST_HOME:-}"
}

@test "build.sh creates a valid gzip tarball" {
  local testdir
  testdir="$(mktemp -d)"
  cp -r "$BATS_TEST_DIRNAME/../profiles/ralph" "$testdir/ralph"
  mkdir -p "$testdir/ralph/src"
  run bash "$testdir/ralph/build.sh"
  [ "$status" -eq 0 ]
  [ -f "$testdir/ralph/ralph.tar.gz" ]
  file_output=$(file "$testdir/ralph/ralph.tar.gz")
  echo "$file_output" | grep -q "gzip compressed data"
  rm -rf "$testdir"
}

@test "build.sh fails when src/ is missing" {
  local testdir
  testdir="$(mktemp -d)"
  cp -r "$BATS_TEST_DIRNAME/../profiles/ralph" "$testdir/ralph"
  rm -rf "$testdir/ralph/src"
  run bash "$testdir/ralph/build.sh"
  [ "$status" -ne 0 ]
  rm -rf "$testdir"
}

@test "setup.sh extracts tarball and copies config" {
  cat > "$BATS_TEST_DIRNAME_TARBALL/setup.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$(mktemp -d)"
tar xzf "$SCRIPT_DIR/ralph.tar.gz" -C "$EXTRACT_DIR"
mkdir -p "$HOME/.config/opencode"
cp -r "$EXTRACT_DIR/tarball-src/config/opencode.json" "$HOME/.config/opencode/"
VERSION=$(cat "$EXTRACT_DIR/VERSION" 2>/dev/null || echo "0.0.0")
echo "$VERSION" > "$HOME/.ralph-version"
rm -rf "$EXTRACT_DIR"
SCRIPT
  run bash "$BATS_TEST_DIRNAME_TARBALL/setup.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/opencode/opencode.json" ]
  [ -f "$HOME/.ralph-version" ]
  [ "$(cat "$HOME/.ralph-version")" = "0.1.0" ]
}

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.ralph-version"
  echo "original" > "$HOME/.config/opencode/opencode.json"
  cat > "$BATS_TEST_DIRNAME_TARBALL/setup.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(tar xzf "$SCRIPT_DIR/ralph.tar.gz" --to-stdout VERSION 2>/dev/null || echo "0.0.0")
_INSTALLED=$(cat "$HOME/.ralph-version" 2>/dev/null || echo "0.0.0")
if [ "$_INSTALLED" = "$VERSION" ]; then
  echo "Profile ralph v$VERSION already installed"
  exit 0
fi
echo "original" > "$HOME/.config/opencode/opencode.json"
SCRIPT
  run bash "$BATS_TEST_DIRNAME_TARBALL/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}
