#!/usr/bin/env bats

setup_file() {
  TESTDIR="$(mktemp -d)"
  export BATS_TEST_DIRNAME_TARBALL="$TESTDIR"
  cp -r "$BATS_TEST_DIRNAME/../profiles/autonomous/src" "$TESTDIR/src"
  rm -f "$TESTDIR/src/config/gsd-config.json"
  echo "0.1.0" > "$TESTDIR/VERSION"
  tar czf "$TESTDIR/autonomous.tar.gz" \
    -C "$TESTDIR/src" config/ skills/ agents/ commands/ \
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

# --- setup.sh idempotency ---

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.autonomous-version"
  echo "original" > "$HOME/.config/opencode/opencode.json"

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(cat "$HOME/.config/opencode/opencode.json")" = "original" ]
  rm -rf "$profiledir"
}

# --- setup.sh graphify / uv handling ---

@test "setup.sh self-installs uv when missing and installs graphify" {
  local profiledir mockdir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  mkdir -p "$mockdir/payload/foo"
  cat > "$mockdir/payload/foo/uv" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "tool" && "$2" == "install" && "$3" == "graphifyy" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\necho graphify 0.1.0\n' > "$HOME/.local/bin/graphify"
  chmod +x "$HOME/.local/bin/graphify"
  echo "uv tool install graphifyy OK" > "$mockdir/uv-call.log"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$mockdir/payload/foo/uv"
  tar czf "$mockdir/uv.tar.gz" -C "$mockdir/payload" foo/

  cat > "$mockdir/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat "$MOCK_UV_TARBALL"
SCRIPT
  chmod +x "$mockdir/curl"

  cat > "$mockdir/npx" <<'SCRIPT'
#!/usr/bin/env bash
echo "gsd installed (mock)" > "$mockdir/npx-call.log"
exit 0
SCRIPT
  chmod +x "$mockdir/npx"

  command() {
    case "$*" in
      *"graphify"*)
        return 1
        ;;
      *"uv"*)
        local resolved
        resolved="$(builtin command -v uv 2>/dev/null || true)"
        if [[ -n "$resolved" && "$resolved" != "$HOME/.local/bin/uv" ]]; then
          return 1
        fi
        ;;
    esac
    builtin command "$@"
  }
  export -f command

  export MOCK_UV_TARBALL="$mockdir/uv.tar.gz"
  export mockdir

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/uv" ]
  [ -f "$mockdir/uv-call.log" ]
  [ -f "$mockdir/npx-call.log" ]
  [ -f "$HOME/.autonomous-version" ]
  [ "$(cat "$HOME/.autonomous-version")" = "0.1.0" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "setup.sh uses existing uv without re-download" {
  local profiledir mockdir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  cat > "$mockdir/uv" <<'SCRIPT'
#!/usr/bin/env bash
echo "uv called: $*" >> "$mockdir/uv-call.log"
if [[ "$1" == "tool" && "$2" == "install" && "$3" == "graphifyy" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\necho graphify 0.1.0\n' > "$HOME/.local/bin/graphify"
  chmod +x "$HOME/.local/bin/graphify"
fi
exit 0
SCRIPT
  chmod +x "$mockdir/uv"

  cat > "$mockdir/curl" <<'SCRIPT'
#!/usr/bin/env bash
touch "$mockdir/curl-called"
exit 0
SCRIPT
  chmod +x "$mockdir/curl"

  cat > "$mockdir/npx" <<'SCRIPT'
#!/usr/bin/env bash
echo "gsd installed (mock)" > "$mockdir/npx-call.log"
exit 0
SCRIPT
  chmod +x "$mockdir/npx"

  command() {
    if [[ "$*" == *"graphify"* ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  export mockdir

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$mockdir/curl-called" ]
  [ -f "$mockdir/uv-call.log" ]
  [ -f "$HOME/.local/bin/graphify" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "autocode command replaces launch-ralph with full pipeline" {
  local dir="$BATS_TEST_DIRNAME/../profiles/autonomous/src/commands"
  [ -f "$dir/autocode.md" ]
  [ ! -f "$dir/launch-ralph.md" ]
  grep -q 'argument-hint: "\[design-doc\]' "$dir/autocode.md"
  grep -q -- "--watch" "$dir/autocode.md"
  grep -q -- "--timeout" "$dir/autocode.md"
  grep -q -- "--prepare-only" "$dir/autocode.md"
  grep -q -- "--skip-prepare" "$dir/autocode.md"
  grep -q "autocode-decider" "$dir/autocode.md"
  grep -q "No design doc found" "$dir/autocode.md"
  grep -q "gsd-autonomous" "$dir/autocode.md"
}

@test "autocode-runner forbids question and mandates decider dispatch" {
  local runner="$BATS_TEST_DIRNAME/../profiles/autonomous/src/agents/autocode-runner.md"
  [ -f "$runner" ]
  grep -q 'NEVER call the .question. tool' "$runner"
  grep -q "autocode-decider" "$runner"
  grep -q "{choice, rationale}" "$runner"
}
