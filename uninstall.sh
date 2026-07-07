#!/usr/bin/env bash
# opencode-pod uninstaller — removes files and Podman artifacts.
set -euo pipefail

DEST_DIR="${HOME}/.local"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST_DIR="${2:?--dest requires an argument}"; shift 2 ;;
    --force) FORCE=true; shift ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [ -f "$SCRIPT_DIR/opencode-pod" ] && [ -d "$SCRIPT_DIR/lib" ]; then
  # shellcheck disable=SC2034
  MODE="local"
else
  # shellcheck disable=SC2034
  MODE="remote"
fi

BIN_DIR="$DEST_DIR/bin"
SHARE_DIR="$DEST_DIR/share/opencode-pod"

printf '=== opencode-pod uninstaller ===\n\n'

printf 'Will remove:\n'
printf '  %s\n' "$BIN_DIR/opencode-pod"
printf '  %s\n' "$SHARE_DIR/lib/distro.sh"
printf '  %s\n' "$SHARE_DIR/lib/podman.sh"
printf '  %s\n' "$SHARE_DIR/lib/security.sh"
printf '  %s\n' "$SHARE_DIR/lib/toml.sh"
printf '  %s\n' "$SHARE_DIR/defaults/opencode-pod.toml"
printf '  %s\n' "$SHARE_DIR/example/opencode-pod.toml"
printf '  %s\n' "$SHARE_DIR/example/opencode.json"
printf '  Podman containers named *opencode-pod*\n'
printf '  Podman volumes named *opencode-pod*\n'
printf '  Podman image cgr.dev/chainguard/wolfi-base:latest\n'
printf '\n'

if ! $FORCE; then
  if [ ! -t 0 ]; then
    printf 'Non-interactive shell. Use --force to skip confirmation.\n' >&2
    exit 1
  fi
  printf 'Continue? [y/N]: '
  read -r reply
  case "$reply" in
    y|Y) ;;
    *) printf 'Aborted.\n' >&2; exit 0 ;;
  esac
fi

# --- File removal ---
for f in \
  "$BIN_DIR/opencode-pod" \
  "$SHARE_DIR/lib/distro.sh" \
  "$SHARE_DIR/lib/podman.sh" \
  "$SHARE_DIR/lib/security.sh" \
  "$SHARE_DIR/lib/toml.sh" \
  "$SHARE_DIR/defaults/opencode-pod.toml" \
  "$SHARE_DIR/example/opencode-pod.toml" \
  "$SHARE_DIR/example/opencode.json"; do
  if [ -f "$f" ]; then
    rm "$f"
    printf '  removed: %s\n' "$f"
  fi
done

rmdir "$SHARE_DIR/lib" 2>/dev/null || true
rmdir "$SHARE_DIR/defaults" 2>/dev/null || true
rmdir "$SHARE_DIR/example" 2>/dev/null || true
rmdir "$SHARE_DIR" 2>/dev/null || true

# --- Podman cleanup ---
if command -v podman &>/dev/null; then
  printf '\n--- Podman artifacts ---\n'

  podman ps -a --filter name=opencode-pod --format '{{.Names}}' 2>/dev/null | while IFS= read -r cname; do
    [ -z "$cname" ] && continue
    podman rm -f "$cname" 2>/dev/null || true
  done

  podman volume ls --filter name=opencode-pod --format '{{.Name}}' 2>/dev/null | while IFS= read -r vname; do
    [ -z "$vname" ] && continue
    podman volume rm "$vname" 2>/dev/null || true
  done

  podman rmi cgr.dev/chainguard/wolfi-base:latest 2>/dev/null || true
fi

printf '\nUninstall complete.\n'
