#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
  export HOME="$TESTDIR/home"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "install.sh creates target directories" {
  run bash install.sh --dest "$HOME/.local" --skip-podman-check
  [ "$status" -eq 0 ]
  [ -d "$HOME/.local/bin" ]
  [ -d "$HOME/.local/share/opencode-pod" ]
  [ -d "$HOME/.local/share/opencode-pod/lib" ]
}

@test "install.sh copies opencode-pod to bin" {
  run bash install.sh --dest "$HOME/.local" --skip-podman-check
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/opencode-pod" ]
  [ -x "$HOME/.local/bin/opencode-pod" ]
}

@test "install.sh copies lib files" {
  run bash install.sh --dest "$HOME/.local" --skip-podman-check
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/share/opencode-pod/lib/toml.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/distro.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/podman.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/security.sh" ]
}

@test "install.sh copies defaults and example" {
  run bash install.sh --dest "$HOME/.local" --skip-podman-check
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/share/opencode-pod/defaults/opencode-pod.toml" ]
  [ -f "$HOME/.local/share/opencode-pod/example/opencode-pod.toml" ]
  [ -f "$HOME/.local/share/opencode-pod/example/opencode.json" ]
}
