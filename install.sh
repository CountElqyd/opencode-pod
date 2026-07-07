#!/usr/bin/env bash
# opencode-pod installer — one-line install via curl | sh
# Works both locally (from repo clone) and remotely (curl-pipe-sh).
set -euo pipefail

REPO="${OP_ENCODE_POD_REPO:-CountElqyd/opencode-pod}"
REF="${OP_ENCODE_POD_VERSION:-main}"
DEST_DIR="${HOME}/.local"
SKIP_PODMAN_CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST_DIR="$2"; shift 2 ;;
    --skip-podman-check) SKIP_PODMAN_CHECK=true; shift ;;
    *) shift ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${REF}"

# Detect local vs remote mode
if [ -f "$SCRIPT_DIR/opencode-pod" ] && [ -d "$SCRIPT_DIR/lib" ]; then
  MODE="local"
else
  MODE="remote"
fi

printf '=== opencode-pod installer ===\n\n'

# --- Distro detection ---
if [[ -f /etc/os-release ]]; then
  if [ "$MODE" = "local" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/distro.sh" 2>/dev/null || true
  else
    DISTRO_SH="$(mktemp)"
    curl -fsSL "$BASE_URL/lib/distro.sh" -o "$DISTRO_SH" 2>/dev/null || true
    # shellcheck disable=SC1091
    [ -f "$DISTRO_SH" ] && source "$DISTRO_SH" 2>/dev/null || true
    rm -f "$DISTRO_SH"
  fi
  detect_distro 2>/dev/null || true
  if [[ "${DISTRO_ID:-unknown}" != "unknown" ]]; then
    printf 'Detected: %s\n' "$DISTRO_ID"
  fi
fi

# --- Podman check ---
if ! $SKIP_PODMAN_CHECK; then
  if command -v podman &>/dev/null; then
    printf 'Podman: installed (%s)\n' "$(podman version -f '{{.Version}}' 2>/dev/null || printf 'unknown')"
  else
    printf 'Podman: not installed\n\n'
    printf 'Install podman for your distribution:\n'
    printf '  %s\n' "${DISTRO_INSTALL_CMD:-See https://podman.io/docs/installation}"
    printf '\n'
    if [[ "${DISTRO_SUBUID_SETUP:-}" == "manual" ]]; then
      printf 'After installing, configure rootless mode:\n'
      printf '  %s\n' "${DISTRO_SUBUID_INSTRUCTIONS:-See rootless tutorial}"
      printf '\n'
    fi
  fi
fi

# --- File installation ---
install_file() {
  local src="$1"
  local dest="$2"
  local mode="${3:-}"
  mkdir -p "$(dirname "$dest")"
  if [ "$MODE" = "local" ]; then
    cp "$SCRIPT_DIR/$src" "$dest"
  else
    curl -fsSL "$BASE_URL/$src" -o "$dest"
  fi
  if [ "$mode" = "exec" ]; then
    chmod +x "$dest"
  fi
}

mkdir -p "$DEST_DIR/bin"
mkdir -p "$DEST_DIR/share/opencode-pod/lib"
mkdir -p "$DEST_DIR/share/opencode-pod/defaults"
mkdir -p "$DEST_DIR/share/opencode-pod/example"

install_file "opencode-pod" "$DEST_DIR/bin/opencode-pod" "exec"

for libfile in distro.sh podman.sh security.sh toml.sh; do
  install_file "lib/$libfile" "$DEST_DIR/share/opencode-pod/lib/$libfile"
done

install_file "defaults/opencode-pod.toml" "$DEST_DIR/share/opencode-pod/defaults/opencode-pod.toml"
install_file "example/opencode-pod.toml" "$DEST_DIR/share/opencode-pod/example/opencode-pod.toml"
install_file "example/opencode.json" "$DEST_DIR/share/opencode-pod/example/opencode.json"

printf '\nInstalled to %s/bin/opencode-pod\n' "$DEST_DIR"
printf '\nMake sure %s/bin is on your PATH:\n' "$DEST_DIR"
printf '  export PATH="%s/bin:$PATH"\n' "$DEST_DIR"
printf '\nThen pull the Wolfi base image:\n'
printf '  podman pull cgr.dev/chainguard/wolfi-base:latest\n'
printf '\nReady. Run "opencode-pod start" in any project directory.\n'
