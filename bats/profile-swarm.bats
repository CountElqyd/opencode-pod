#!/usr/bin/env bats

setup_file() {
  TESTDIR="$(mktemp -d)"
  export BATS_TEST_DIRNAME_TARBALL="$TESTDIR"
  mkdir -p "$TESTDIR/src/config"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/src/config/opencode-swarm.json" "$TESTDIR/src/config/opencode-swarm.json"
  echo "0.1.0" > "$TESTDIR/VERSION"
  tar czf "$TESTDIR/swarm.tar.gz" \
    -C "$TESTDIR/src" config/ \
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

# --- build.sh ---

@test "build.sh creates a valid gzip tarball" {
  local testdir
  testdir="$(mktemp -d)"
  cp -r "$BATS_TEST_DIRNAME/../profiles/swarm" "$testdir/swarm"
  mkdir -p "$testdir/swarm/src/config"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/src/config/opencode-swarm.json" "$testdir/swarm/src/config/opencode-swarm.json"
  printf '{"profiles":[{"name":"swarm","version":"0.1.0"}]}\n' > "$testdir/index.json"
  run bash "$testdir/swarm/build.sh"
  [ "$status" -eq 0 ]
  [ -f "$testdir/swarm/swarm.tar.gz" ]
  file_output=$(file "$testdir/swarm/swarm.tar.gz")
  echo "$file_output" | grep -q "gzip compressed data"
  rm -rf "$testdir"
}

@test "build.sh fails when src/ is missing" {
  local testdir
  testdir="$(mktemp -d)"
  cp -r "$BATS_TEST_DIRNAME/../profiles/swarm" "$testdir/swarm"
  rm -rf "$testdir/swarm/src"
  run bash "$testdir/swarm/build.sh"
  [ "$status" -ne 0 ]
  rm -rf "$testdir"
}

# --- profile.json ---

@test "profile.json is valid JSON" {
  python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../profiles/swarm/profile.json') as f:
    data = json.load(f)
assert data['name'] == 'swarm'
assert 'components' in data
assert data['network'] == 'bridge'
"
}

# --- opencode-swarm.json ---

@test "opencode-swarm.json is valid JSON with correct structure" {
  python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../profiles/swarm/src/config/opencode-swarm.json') as f:
    data = json.load(f)
agents = data['agents']
for role in ['architect', 'coder', 'reviewer', 'test_engineer', 'explorer']:
    assert role in agents, f'Missing agent: {role}'
    assert agents[role]['model'] == 'opencode/deepseek-v4-flash-free', f'{role} model mismatch'
assert data['session_mode'] == 'balanced'
assert data['project_mode'] == 'balanced'
assert data['max_parallel_coders'] == 1
assert data['council'] == False
assert data['ui_review'] == False
assert data['mutation_testing'] == False
"
}

# --- VERSION consistency ---

@test "index.json version is 0.1.0 for swarm" {
  python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../profiles/index.json') as f:
    idx = json.load(f)
for entry in idx['profiles']:
    if entry['name'] == 'swarm':
        assert entry['version'] == '0.1.0', 'index.json version mismatch'
        break
else:
    assert False, 'swarm not found in index.json'
"
}

# --- setup.sh environment validation ---

@test "setup.sh fails when tarball is missing" {
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"swarm.tar.gz not found"* ]]
  rm -rf "$profiledir"
}

# --- setup.sh idempotency ---

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.swarm-version"
  echo "original" > "$HOME/.config/opencode/opencode-swarm.json"

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/swarm.tar.gz" "$profiledir/swarm.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(cat "$HOME/.config/opencode/opencode-swarm.json")" = "original" ]
  rm -rf "$profiledir"
}

# --- setup.sh npm validation ---

@test "setup.sh fails when npm is not available" {
  command() {
    if [[ "$*" == *"npm" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/swarm.tar.gz" "$profiledir/swarm.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"npm not found"* ]]
  rm -rf "$profiledir"
}

# --- setup.sh with mocked npm ---

@test "setup.sh extracts tarball and copies config" {
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/swarm.tar.gz" "$profiledir/swarm.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  cat > "$mockdir/npm" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  cat > "$mockdir/opencode-swarm" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$mockdir/npm" "$mockdir/opencode-swarm"

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/opencode/opencode-swarm.json" ]
  [ -f "$HOME/.swarm-version" ]
  [ "$(cat "$HOME/.swarm-version")" = "0.1.0" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "setup.sh copies config with correct content" {
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/swarm.tar.gz" "$profiledir/swarm.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  cat > "$mockdir/npm" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  cat > "$mockdir/opencode-swarm" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$mockdir/npm" "$mockdir/opencode-swarm"

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]

  python3 -c "
import json
with open('$HOME/.config/opencode/opencode-swarm.json') as f:
    data = json.load(f)
assert data['agents']['architect']['model'] == 'opencode/deepseek-v4-flash-free'
assert data['session_mode'] == 'balanced'
"
  rm -rf "$profiledir" "$mockdir"
}
