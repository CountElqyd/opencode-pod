#!/usr/bin/env bash
# opencode-pod installer — one-line install via curl | sh
# Detects distro, prints podman install instructions, copies files.

set -euo pipefail

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

printf '=== opencode-pod installer ===\n\n'

if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/distro.sh" 2>/dev/null || true
  detect_distro 2>/dev/null || true
  if [[ "${DISTRO_ID:-unknown}" != "unknown" ]]; then
    printf 'Detected: %s\n' "$DISTRO_ID"
  fi
fi

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

mkdir -p "$DEST_DIR/bin"
mkdir -p "$DEST_DIR/share/opencode-pod/lib"
mkdir -p "$DEST_DIR/share/opencode-pod/defaults"
mkdir -p "$DEST_DIR/share/opencode-pod/example"

cp "$SCRIPT_DIR/opencode-pod" "$DEST_DIR/bin/opencode-pod"
chmod +x "$DEST_DIR/bin/opencode-pod"

for libfile in "$SCRIPT_DIR/lib/"*.sh; do
  [[ -f "$libfile" ]] && cp "$libfile" "$DEST_DIR/share/opencode-pod/lib/"
done

cp "$SCRIPT_DIR/defaults/opencode-pod.toml" "$DEST_DIR/share/opencode-pod/defaults/" 2>/dev/null || true
cp "$SCRIPT_DIR/example/opencode-pod.toml" "$DEST_DIR/share/opencode-pod/example/" 2>/dev/null || true
cp "$SCRIPT_DIR/example/opencode.json" "$DEST_DIR/share/opencode-pod/example/" 2>/dev/null || true

printf '\nInstalled to %s/bin/opencode-pod\n' "$DEST_DIR"
printf '\nMake sure %s/bin is on your PATH:\n' "$DEST_DIR"
printf '  export PATH="%s/bin:$PATH"\n' "$DEST_DIR"
printf '\nThen pull the Wolfi base image:\n'
printf '  podman pull cgr.dev/chainguard/wolfi-base:latest\n'
printf '\nReady. Run "opencode-pod start" in any project directory.\n'
