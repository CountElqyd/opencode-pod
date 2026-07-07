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

@test "install.sh downloads files in remote mode (no local lib)" {
  REMOTE_DIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../install.sh" "$REMOTE_DIR/"

  # Mock curl: creates output files with fake content
  cat > "$REMOTE_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift; mkdir -p "$(dirname "$1")"; echo "fake" > "$1" ;;
    *) ;;
  esac
  shift
done
MOCK
  chmod +x "$REMOTE_DIR/curl"

  run env "PATH=$REMOTE_DIR:$PATH" bash "$REMOTE_DIR/install.sh" --dest "$HOME/.local" --skip-podman-check
  echo "status=$status output=$output"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/opencode-pod" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/toml.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/distro.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/podman.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/lib/security.sh" ]
  [ -f "$HOME/.local/share/opencode-pod/defaults/opencode-pod.toml" ]
  [ -f "$HOME/.local/share/opencode-pod/example/opencode-pod.toml" ]
  [ -f "$HOME/.local/share/opencode-pod/example/opencode.json" ]
}

@test "install.sh remote mode uses REPO/REF for URLs" {
  REMOTE_DIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/../install.sh" "$REMOTE_DIR/"

  cat > "$REMOTE_DIR/curl" <<'MOCK'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) shift; out="$1"; mkdir -p "$(dirname "$out")"; echo "ref=$OP_ENCODE_POD_VERSION" > "$out" ;;
    *) ;;
  esac
  shift
done
MOCK
  chmod +x "$REMOTE_DIR/curl"

  run env "PATH=$REMOTE_DIR:$PATH" OP_ENCODE_POD_VERSION=v0.1.0 bash "$REMOTE_DIR/install.sh" --dest "$HOME/.local" --skip-podman-check
  [ "$status" -eq 0 ]
  grep -q "ref=v0.1.0" "$HOME/.local/bin/opencode-pod"
}
