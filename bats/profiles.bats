#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TESTDIR"
}

# --- github_raw_url ---

@test "github_raw_url defaults to CountElqyd/opencode-pod main" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run github_raw_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://raw.githubusercontent.com/CountElqyd/opencode-pod/main" ]
}

@test "github_raw_url respects OPCODE_POD_REPO" {
  export OPCODE_POD_REPO="myuser/myrepo"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run github_raw_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://raw.githubusercontent.com/myuser/myrepo/main" ]
}

@test "github_raw_url respects OPCODE_POD_VERSION" {
  export OPCODE_POD_VERSION="v1.0.0"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run github_raw_url
  [ "$status" -eq 0 ]
  [ "$output" = "https://raw.githubusercontent.com/CountElqyd/opencode-pod/v1.0.0" ]
}

# --- cmd_profile_list ---

@test "cmd_profile_list prints table with installed column" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  cd "$TESTDIR"
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0"}]}'; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Ralph profile"},{"name":"ai","version":"2.0.0","description":"AI profile"}]}'; }
  python3() { command python3 "$@"; }
  export -f _load_registry _fetch_index python3
  run cmd_profile_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"INSTALLED"* ]]
  [[ "$output" == *"ralph"* ]]
  [[ "$output" == *"1.0.0"* ]]
}

@test "cmd_profile_list shows — for not installed" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  cd "$TESTDIR"
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Ralph profile"}]}'; }
  python3() { command python3 "$@"; }
  export -f _load_registry _fetch_index python3
  run cmd_profile_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"—"* ]]
}

@test "cmd_profile_list handles network failure" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() { return 1; }
  export -f _fetch_index
  run cmd_profile_list
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to fetch profile index"* ]]
}

@test "cmd_profile_list handles invalid JSON" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() { printf 'not-json'; return 0; }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  python3() { command python3 "$@"; }
  export -f _fetch_index _load_registry python3
  run cmd_profile_list
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid profile index format"* ]]
}

# --- cmd_profile_info ---

@test "cmd_profile_info requires name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_info
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cmd_profile_info rejects invalid name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_info "ralph space"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "cmd_profile_info unknown profile" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() {
    printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0","description":"Existing"}]}'
  }
  export -f _fetch_index
  run cmd_profile_info "unknown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "cmd_profile_info handles network failure" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() { return 1; }
  export -f _fetch_index
  run cmd_profile_info "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to fetch profile index"* ]]
}

@test "cmd_profile_info displays metadata from index" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() {
    printf '{"format_version":2,"profiles":[{"name":"ralph","version":"0.2.0","description":"Test profile","path":"profiles/ralph/","author":"Ralph","components":{"skills":5,"agents":3,"commands":2,"fabric_mcp":true,"gsd_core":"1.0.0"},"requires":["nodejs"],"network":"host"}]}'
  }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"0.2.0"}]}'; }
  python3() { command python3 "$@"; }
  export -f _fetch_index _load_registry python3
  run cmd_profile_info ralph
  [ "$status" -eq 0 ]
  [[ "$output" == *"ralph"* ]]
  [[ "$output" == *"0.2.0"* ]]
  [[ "$output" == *"Test profile"* ]]
  [[ "$output" == *"Ralph"* ]]
  [[ "$output" == *"5"* ]]
  [[ "$output" == *"3"* ]]
  [[ "$output" == *"host"* ]]
  [[ "$output" == *"Installed"* ]]
}

@test "cmd_profile_info shows version diff when installed version differs" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() {
    printf '{"format_version":2,"profiles":[{"name":"ralph","version":"0.3.0","description":"Newer","path":"profiles/ralph/","author":"Ralph","components":{},"network":""}]}'
  }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"0.2.0"}]}'; }
  python3() { command python3 "$@"; }
  export -f _fetch_index _load_registry python3
  run cmd_profile_info ralph
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.3.0"* ]]
  [[ "$output" == *"0.2.0"* ]]
}

@test "cmd_profile_info shows remote-only when not installed" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  _fetch_index() {
    printf '{"format_version":2,"profiles":[{"name":"ralph","version":"0.2.0","description":"Test","path":"profiles/ralph/","author":"Ralph","components":{},"network":""}]}'
  }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  python3() { command python3 "$@"; }
  export -f _fetch_index _load_registry python3
  run cmd_profile_info ralph
  [ "$status" -eq 0 ]
  [[ "$output" != *"Installed"* ]]
}

# --- cmd_profile_install ---

_fake_resolve() {
  CONTAINER_NAME="opencode-pod-test-abc123"
  CONTAINER_STATE="${1:-running}"
  export CONTAINER_NAME CONTAINER_STATE
}

@test "cmd_profile_install requires name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cmd_profile_install rejects invalid name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_install "../evil"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "cmd_profile_install fails when container nonexistent" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { CONTAINER_STATE="nonexistent"; export CONTAINER_STATE; return 0; }
  export -f resolve_project
  run cmd_profile_install "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"setup'"* ]]
}

@test "cmd_profile_install already installed without --force" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0"}]}'; }
  export -f resolve_project _load_registry _fake_resolve
  run cmd_profile_install "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Already installed"* ]]
}

@test "cmd_profile_install --force re-installs even if installed" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0"}]}'; }
  _save_registry() { :; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","components":{},"network":""}]}'; }
  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_called"; return 0; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _save_registry _fetch_index podman python3 _fake_resolve
  run cmd_profile_install "ralph" "--force"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed"* ]]
  [[ "$(cat "$TESTDIR/podman_called")" == *"exec"* ]]
  [[ "$(cat "$TESTDIR/podman_called")" == *"ralph"* ]]
}

@test "cmd_profile_install success execs setup inside container" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  _save_registry() { :; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","components":{},"network":""}]}'; }
  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_called"; return 0; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _save_registry _fetch_index podman python3 _fake_resolve
  run cmd_profile_install "ralph"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed"* ]]
  [[ "$output" == *"1.0.0"* ]]
  local podman_args
  podman_args="$(cat "$TESTDIR/podman_called")"
  [[ "$podman_args" == *"exec"* ]]
  [[ "$podman_args" == *"-u dev"* ]]
  [[ "$podman_args" == *"opencode-pod-test-abc123"* ]]
  [[ "$podman_args" == *"curl"* ]]
  [[ "$podman_args" == *"setup.sh"* ]]
  [[ "$podman_args" == *"ralph.tar.gz"* ]]
  [[ "$podman_args" == *"/tmp/.opencode-profile-ralph"* ]]
}

@test "cmd_profile_install start container if stopped" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve "exited"; }
  podman() {
    if [[ "$*" == "start"* ]]; then
      printf started > "$TESTDIR/start_called"
      return 0
    fi
    printf '%s\n' "$*" > "$TESTDIR/podman_called"; return 0
  }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  _save_registry() { :; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","components":{},"network":""}]}'; }
  python3() { command python3 "$@"; }
  export -f resolve_project podman _load_registry _save_registry _fetch_index python3 _fake_resolve
  run cmd_profile_install "ralph"
  [ "$status" -eq 0 ]
  [ -f "$TESTDIR/start_called" ]
}

@test "cmd_profile_install setup failure not recorded in registry" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  _save_registry() { printf 'SAVED=%s\n' "$1" > "$TESTDIR/saved_registry"; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","components":{},"network":""}]}'; }
  podman() { return 1; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _save_registry _fetch_index podman python3 _fake_resolve
  run cmd_profile_install "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed"* ]]
  [ ! -f "$TESTDIR/saved_registry" ]
}

@test "cmd_profile_install unknown profile" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"other","version":"1.0","description":"Other"}]}'; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _fetch_index python3 _fake_resolve
  run cmd_profile_install "unknown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# --- cmd_profile_update ---

@test "cmd_profile_update requires name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cmd_profile_update rejects invalid name" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_update "ralph space"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid profile name"* ]]
}

@test "cmd_profile_update fails when container nonexistent" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { CONTAINER_STATE="nonexistent"; export CONTAINER_STATE; return 0; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0"}]}'; }
  export -f resolve_project _load_registry
  run cmd_profile_update "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"setup'"* ]]
}

@test "cmd_profile_update not installed" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[]}'; }
  export -f resolve_project _load_registry _fake_resolve
  run cmd_profile_update "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "cmd_profile_update same version skips without --force" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0"}]}'; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","components":{},"network":""}]}'; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _fetch_index python3 _fake_resolve
  run cmd_profile_update "ralph"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at"* ]]
}

@test "cmd_profile_update with version diff execs setup" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"0.1.0"}]}'; }
  _save_registry() { :; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"0.2.0","description":"New","components":{},"network":""}]}'; }
  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_called"; return 0; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _save_registry _fetch_index podman python3 _fake_resolve
  run cmd_profile_update "ralph"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.1.0"* ]]
  [[ "$output" == *"0.2.0"* ]]
  [[ "$output" == *"updated"* ]]
  [[ "$(cat "$TESTDIR/podman_called")" == *"exec"* ]]
}

@test "cmd_profile_update setup failure not recorded in registry" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  resolve_project() { _fake_resolve; }
  _load_registry() { printf '{"format_version":1,"profiles":[{"name":"ralph","version":"0.1.0"}]}'; }
  _save_registry() { printf 'SAVED=%s\n' "$1" > "$TESTDIR/saved_registry"; }
  _fetch_index() { printf '{"format_version":2,"profiles":[{"name":"ralph","version":"0.2.0","description":"New","components":{},"network":""}]}'; }
  podman() { return 1; }
  python3() { command python3 "$@"; }
  export -f resolve_project _load_registry _save_registry _fetch_index podman python3 _fake_resolve
  run cmd_profile_update "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed"* ]]
  [ ! -f "$TESTDIR/saved_registry" ]
}

@test "cmd_profile_update network mode prompt when mode changes" {
  skip "Network mode prompt test requires interactive terminal simulation"
}

# --- Helper tests ---

@test "_profile_registry_path returns XDG path" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  export XDG_DATA_HOME="/custom/data"
  run _profile_registry_path
  [ "$status" -eq 0 ]
  [ "$output" = "/custom/data/opencode-pod/profiles.json" ]
}

@test "_profile_registry_path falls back to HOME" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  unset XDG_DATA_HOME
  HOME="/home/testuser"
  run _profile_registry_path
  [ "$status" -eq 0 ]
  [ "$output" = "/home/testuser/.local/share/opencode-pod/profiles.json" ]
}

@test "_load_registry returns empty JSON when file missing" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  export XDG_DATA_HOME="$TESTDIR"
  run _load_registry
  [ "$status" -eq 0 ]
  [[ "$output" == *"format_version"* ]]
  [[ "$output" == *'"profiles":[]'* ]]
}

@test "_save_registry writes valid JSON" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  export XDG_DATA_HOME="$TESTDIR"
  local test_json='{"format_version":1,"profiles":[{"name":"test","version":"1.0"}]}'
  run _save_registry "$test_json"
  [ "$status" -eq 0 ]
  [[ "$(cat "$TESTDIR/opencode-pod/profiles.json")" == "$test_json" ]]
}

@test "_save_registry path field is empty string for container-exec installs" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  export XDG_DATA_HOME="$TESTDIR"
  local test_json='{"format_version":1,"profiles":[{"name":"ralph","version":"1.0.0","description":"Test","path":"","installed_at":"2026-07-19T00:00:00Z"}]}'
  run _save_registry "$test_json"
  [ "$status" -eq 0 ]
  local saved
  saved="$(cat "$TESTDIR/opencode-pod/profiles.json")"
  [[ "$saved" == *'"path":""'* ]]
  [[ "$saved" == *'"ralph"'* ]]
}
