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

@test "cmd_profile_list prints table for valid index" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() { printf '{"profiles":[{"name":"ralph","version":"1.0.0","description":"Ralph profile"},{"name":"ai","version":"2.0.0","description":"AI profile"}]}'; return 0; }
  python3() { command python3 "$@"; }
  export -f curl python3
  run cmd_profile_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"NAME"* ]]
  [[ "$output" == *"VERSION"* ]]
  [[ "$output" == *"DESCRIPTION"* ]]
  [[ "$output" == *"ralph"* ]]
  [[ "$output" == *"1.0.0"* ]]
  [[ "$output" == *"Ralph profile"* ]]
  [[ "$output" == *"ai"* ]]
  [[ "$output" == *"2.0.0"* ]]
}

@test "cmd_profile_list handles network failure" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() { return 1; }
  export -f curl
  run cmd_profile_list
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unable to fetch profile index"* ]]
}

@test "cmd_profile_list handles invalid JSON" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() { printf 'not-json'; return 0; }
  python3() { command python3 "$@"; }
  export -f curl python3
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
  curl() { return 1; }
  export -f curl
  run cmd_profile_info "unknown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "cmd_profile_info displays metadata" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() {
    printf '{"name":"ralph","version":"0.2.0","description":"Test","author":"Ralph","components":{"skills":5,"agents":3,"commands":2,"fabric_mcp":true,"gsd_core":"1.0.0"},"requires":["nodejs"],"network":"host"}'
    return 0
  }
  python3() { command python3 "$@"; }
  export -f curl python3

  run cmd_profile_info ralph
  [ "$status" -eq 0 ]
  [[ "$output" == *"ralph"* ]]
  [[ "$output" == *"0.2.0"* ]]
  [[ "$output" == *"Test"* ]]
  [[ "$output" == *"Ralph"* ]]
  [[ "$output" == *"5"* ]]
  [[ "$output" == *"3"* ]]
  [[ "$output" == *"host"* ]]
}

# --- cmd_profile_install ---

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

@test "cmd_profile_install already installed" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  mkdir -p "./profiles/ralph"
  run cmd_profile_install "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Already installed"* ]]
}

@test "cmd_profile_install unknown profile" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() { return 1; }
  export -f curl
  run cmd_profile_install "unknown"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "cmd_profile_install success" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() {
    case "$*" in
      *profile.json*) printf '{"name":"ralph","version":"1.0.0","components":{},"network":""}' ;;
      *ralph.tar.gz*) mkdir -p "./profiles/ralph"; printf 'fake-tarball' > "./profiles/ralph/ralph.tar.gz" ;;
      *setup.sh*) printf '#!/bin/bash\necho hello' > "./profiles/ralph/setup.sh" ;;
    esac
    return 0
  }
  python3() { command python3 "$@"; }
  export -f curl python3
  run cmd_profile_install "ralph"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile 'ralph' (v1.0.0) installed"* ]]
  [[ "$output" == *"setup.sh"* ]]
  [ -x "./profiles/ralph/setup.sh" ]
  [ -f "./profiles/ralph/ralph.tar.gz" ]
}

@test "cmd_profile_install tarball download failure" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() {
    if [[ "$*" == *"profile.json"* ]]; then
      printf '{"name":"ralph","version":"1.0.0","components":{},"network":""}'
      return 0
    fi
    return 1
  }
  python3() { command python3 "$@"; }
  export -f curl python3
  run cmd_profile_install "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to download"* ]]
  [ ! -d "./profiles/ralph" ]
}

@test "cmd_profile_install setup.sh download failure cleans up" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  curl() {
    case "$*" in
      *profile.json*) printf '{"name":"ralph","version":"0.2.0"}' ;;
      *ralph.tar.gz*) printf 'fake-tarball' > "$TESTDIR/profiles/ralph/ralph.tar.gz" ;;
      *setup.sh*) return 1 ;;
    esac
    return 0
  }
  python3() { command python3 "$@"; }
  export -f curl python3

  run cmd_profile_install ralph
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to download"* ]]
  [ ! -d "$TESTDIR/profiles/ralph" ]
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

@test "cmd_profile_update not installed" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  run cmd_profile_update "ralph"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "cmd_profile_update success" {
  cd "$TESTDIR"
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  mkdir -p "./profiles/ralph"
  touch "./profiles/ralph/ralph.tar.gz"
  touch "./profiles/ralph/setup.sh"
  chmod -x "./profiles/ralph/setup.sh"
  curl() {
    case "$*" in
      *ralph.tar.gz*) printf 'updated-tarball' > "./profiles/ralph/ralph.tar.gz" ;;
      *setup.sh*) printf '#!/bin/bash\necho updated' > "./profiles/ralph/setup.sh" ;;
    esac
    return 0
  }
  export -f curl
  run cmd_profile_update "ralph"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile 'ralph' updated"* ]]
  [ -x "./profiles/ralph/setup.sh" ]
  [ -f "./profiles/ralph/ralph.tar.gz" ]
}

@test "cmd_profile_update tarball download failure" {
  source "$BATS_TEST_DIRNAME/../lib/profiles.sh"
  mkdir -p "$TESTDIR/profiles/ralph"
  cd "$TESTDIR"

  curl() { return 1; }
  export -f curl

  run cmd_profile_update ralph
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to download"* ]]
}
