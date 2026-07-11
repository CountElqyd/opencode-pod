#!/usr/bin/env bats

setup_file() {
  TESTDIR="$(mktemp -d)"
  export BATS_TEST_DIRNAME_TARBALL="$TESTDIR"
  mkdir -p "$TESTDIR/src/config" "$TESTDIR/src/skills" "$TESTDIR/src/agents"
  echo '{"permissions":{}}' > "$TESTDIR/src/config/opencode.json"
  echo "# test skill" > "$TESTDIR/src/skills/test.md"
  echo "# test agent" > "$TESTDIR/src/agents/test.md"
  echo "0.1.0" > "$TESTDIR/VERSION"
  tar czf "$TESTDIR/ralph.tar.gz" \
    -C "$TESTDIR/src" config/ skills/ agents/ \
    -C "$TESTDIR" VERSION
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
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/ralph.tar.gz" "$profiledir/ralph.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/ralph/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/opencode/opencode.json" ]
  [ -f "$HOME/.ralph-version" ]
  [ "$(cat "$HOME/.ralph-version")" = "0.1.0" ]
  rm -rf "$profiledir"
}

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.ralph-version"
  echo "original" > "$HOME/.config/opencode/opencode.json"

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/ralph.tar.gz" "$profiledir/ralph.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/ralph/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(cat "$HOME/.config/opencode/opencode.json")" = "original" ]
  rm -rf "$profiledir"
}
