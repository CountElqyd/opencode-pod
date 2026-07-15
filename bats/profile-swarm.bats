#!/usr/bin/env bats

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.config/opencode"
}

teardown() {
  rm -rf "${TEST_HOME:-}"
}

# --- build.sh ---

@test "build.sh is a no-op stub" {
  run bash "$BATS_TEST_DIRNAME/../profiles/swarm/build.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tarball"* ]]
}

# --- profile.json ---

@test "profile.json is valid JSON" {
  python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../profiles/swarm/profile.json') as f:
    data = json.load(f)
assert data['name'] == 'swarm'
assert data['version'] == '0.1.0'
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

@test "VERSION matches across profile files" {
  VERSION=$(cat "$BATS_TEST_DIRNAME/../profiles/swarm/VERSION")
  python3 -c "
import json
with open('$BATS_TEST_DIRNAME/../profiles/swarm/profile.json') as f:
    p = json.load(f)
with open('$BATS_TEST_DIRNAME/../profiles/index.json') as f:
    idx = json.load(f)
assert p['version'] == '$VERSION', 'profile.json version mismatch'
for entry in idx['profiles']:
    if entry['name'] == 'swarm':
        assert entry['version'] == '$VERSION', 'index.json version mismatch'
        break
else:
    assert False, 'swarm not found in index.json'
"
}

# --- setup.sh environment validation ---

@test "setup.sh fails when VERSION file is missing" {
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VERSION file not found"* ]]
  rm -rf "$profiledir"
}

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.swarm-version"

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/VERSION" "$profiledir/VERSION"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  rm -rf "$profiledir"
}

# --- setup.sh with mocked npm ---

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
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/VERSION" "$profiledir/VERSION"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"npm not found"* ]]
  rm -rf "$profiledir"
}

@test "setup.sh installs and copies config" {
  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/VERSION" "$profiledir/VERSION"
  mkdir -p "$profiledir/src/config"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/src/config/opencode-swarm.json" "$profiledir/src/config/opencode-swarm.json"
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
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/setup.sh" "$profiledir/setup.sh"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/VERSION" "$profiledir/VERSION"
  mkdir -p "$profiledir/src/config"
  cp "$BATS_TEST_DIRNAME/../profiles/swarm/src/config/opencode-swarm.json" "$profiledir/src/config/opencode-swarm.json"
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
