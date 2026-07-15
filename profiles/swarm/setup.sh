#!/usr/bin/env bash
# Swarm profile installer — run inside opencode-pod container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"

cleanup() {
  local rc=$?
  if [ $rc -ne 0 ]; then
    echo "Swarm profile installation failed. Re-run setup.sh to retry." >&2
  fi
}
trap cleanup EXIT

# ---- Environment validation ----
if [ ! -f "$VERSION_FILE" ]; then
  echo "Error: VERSION file not found at $VERSION_FILE" >&2
  exit 1
fi

if [ ! -d "$HOME" ]; then
  echo "Error: HOME ($HOME) does not exist" >&2
  exit 1
fi

VERSION=$(cat "$VERSION_FILE")

# ---- Idempotency guard ----
INSTALLED=$(cat "$HOME/.swarm-version" 2>/dev/null || echo "0.0.0")

if [ "$INSTALLED" = "$VERSION" ]; then
  echo "Swarm profile v$VERSION already installed"
  exit 0
fi

echo "Installing Swarm profile v$VERSION..."

# ---- Install opencode-swarm ----
if ! command -v npm &>/dev/null; then
  echo "Error: npm not found" >&2
  exit 1
fi

echo "  Installing opencode-swarm via npm..."
if ! npm install -g opencode-swarm 2>&1; then
  echo "Error: npm install failed" >&2
  exit 1
fi

echo "  Running opencode-swarm installer..."
if ! opencode-swarm install 2>&1; then
  echo "Error: opencode-swarm install failed" >&2
  exit 1
fi

# ---- Copy pre-configured config ----
CONFIG_SRC="$SCRIPT_DIR/src/config/opencode-swarm.json"
if [ -f "$CONFIG_SRC" ]; then
  mkdir -p "$HOME/.config/opencode"
  cp "$CONFIG_SRC" "$HOME/.config/opencode/opencode-swarm.json"
  echo "  Config: opencode-swarm.json installed"
fi

# ---- Record version ----
echo "$VERSION" > "$HOME/.swarm-version"
echo "Swarm profile v$VERSION installed successfully"
