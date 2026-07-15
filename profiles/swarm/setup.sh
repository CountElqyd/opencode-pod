#!/usr/bin/env bash
# Swarm profile installer — run inside opencode-pod container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SCRIPT_DIR/swarm.tar.gz"
EXTRACT_DIR=""

cleanup() {
  local rc=$?
  if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
    rm -rf "$EXTRACT_DIR"
  fi
  if [ $rc -ne 0 ]; then
    echo "Swarm profile installation failed. Re-run setup.sh to retry." >&2
  fi
}
trap cleanup EXIT

# ---- Environment validation ----
if [ ! -f "$TARBALL" ]; then
  echo "Error: $TARBALL not found" >&2
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "Error: HOME ($HOME) does not exist" >&2
  exit 1
fi

# ---- Idempotency guard ----
VERSION=$(tar xzOf "$TARBALL" VERSION 2>/dev/null || echo "0.0.0")
INSTALLED=$(cat "$HOME/.swarm-version" 2>/dev/null || echo "0.0.0")

if [ "$INSTALLED" = "$VERSION" ]; then
  echo "Swarm profile v$VERSION already installed"
  exit 0
fi

echo "Installing Swarm profile v$VERSION..."

# ---- Extract tarball ----
EXTRACT_DIR="$(mktemp -d)"
tar xzf "$TARBALL" -C "$EXTRACT_DIR"
EXTRACTED="$EXTRACT_DIR"

# ---- Install opencode-swarm ----
if ! command -v npm &>/dev/null; then
  echo "Error: npm not found" >&2
  exit 1
fi

echo "  Installing opencode-swarm via npm..."
if ! npm install -g opencode-swarm; then
  echo "Error: npm install failed" >&2
  exit 1
fi

echo "  Running opencode-swarm installer..."
if ! opencode-swarm install; then
  echo "Error: opencode-swarm install failed" >&2
  exit 1
fi

# ---- Copy config ----
mkdir -p "$HOME/.config/opencode"
if [ -f "$EXTRACTED/config/opencode-swarm.json" ]; then
  cp "$EXTRACTED/config/opencode-swarm.json" "$HOME/.config/opencode/opencode-swarm.json"
  echo "  Config: opencode-swarm.json installed"
fi

# ---- Record version ----
echo "$VERSION" > "$HOME/.swarm-version"
echo "Swarm profile v$VERSION installed successfully"
