#!/usr/bin/env bash
# Autonomous profile installer — run inside opencode-pod container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SCRIPT_DIR/autonomous.tar.gz"
EXTRACT_DIR=""

cleanup() {
  if [ -n "$EXTRACT_DIR" ] && [ -d "$EXTRACT_DIR" ]; then
    rm -rf "$EXTRACT_DIR"
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
INSTALLED=$(cat "$HOME/.autonomous-version" 2>/dev/null || echo "0.0.0")

if [ "$INSTALLED" = "$VERSION" ]; then
  echo "Autonomous profile v$VERSION already installed"
  exit 0
fi

echo "Installing Autonomous profile v$VERSION..."

# ---- Extract tarball ----
EXTRACT_DIR="$(mktemp -d)"
tar xzf "$TARBALL" -C "$EXTRACT_DIR"
EXTRACTED="$EXTRACT_DIR"

# ---- Copy OpenCode config ----
mkdir -p "$HOME/.config/opencode"
if [ -f "$EXTRACTED/config/opencode.json" ]; then
  cp "$EXTRACTED/config/opencode.json" "$HOME/.config/opencode/"
  echo "  Config: opencode.json installed"
fi

# ---- Copy GSD project config template (non-clobbering) ----
if [ -f "$EXTRACTED/config/gsd-config.json" ]; then
  mkdir -p /workspace/.planning
  if [ ! -f /workspace/.planning/config.json ]; then
    cp "$EXTRACTED/config/gsd-config.json" /workspace/.planning/config.json
    echo "  GSD config: /workspace/.planning/config.json seeded"
  else
    echo "  GSD config: existing /workspace/.planning/config.json kept"
  fi
fi

# ---- Copy skills ----
if [ -d "$EXTRACTED/skills" ]; then
  mkdir -p "$HOME/.config/opencode/skills"
  cp -r "$EXTRACTED/skills/"* "$HOME/.config/opencode/skills/" 2>/dev/null
  echo "  Skills: installed"
fi

# ---- Copy agents ----
if [ -d "$EXTRACTED/agents" ]; then
  mkdir -p "$HOME/.config/opencode/agents"
  cp -r "$EXTRACTED/agents/"* "$HOME/.config/opencode/agents/" 2>/dev/null
  echo "  Agents: installed"
fi

# ---- Copy commands ----
if [ -d "$EXTRACTED/commands" ]; then
  mkdir -p "$HOME/.config/opencode/command"
  cp -r "$EXTRACTED/commands/"* "$HOME/.config/opencode/command/" 2>/dev/null
  echo "  Commands: installed"
fi

# ---- Copy plugins ----
if [ -d "$EXTRACTED/plugins" ]; then
  mkdir -p "$HOME/.config/opencode/plugins"
  cp -r "$EXTRACTED/plugins/"* "$HOME/.config/opencode/plugins/" 2>/dev/null
  echo "  Plugins: installed"
fi

# ---- Add ~/.local/bin to PATH ----
grep -qs '\.local/bin' "$HOME/.zshenv" 2>/dev/null || {
  # shellcheck disable=SC2016
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshenv"
  echo "  PATH: ~/.local/bin added to \$HOME/.zshenv"
}
# shellcheck disable=SC1091
. "$HOME/.zshenv"

# ---- Install Graphify CLI ----
UV_BIN="$HOME/.local/bin/uv"
if command -v graphify &>/dev/null; then
  echo "  Graphify: already installed ($(graphify --version 2>/dev/null || echo 'unknown'))"
else
  if ! command -v uv &>/dev/null && [ ! -x "$UV_BIN" ]; then
    echo "  Graphify: installing uv..."
    mkdir -p "$HOME/.local/bin"
    curl -LsSf https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-unknown-linux-gnu.tar.gz | tar xz -C "$HOME/.local/bin" --strip-components=1
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if command -v uv &>/dev/null; then
    echo "  Graphify: installing via uv..."
    uv tool install graphifyy || {
      echo "  Warning: graphifyy install failed" >&2
    }
  else
    echo "  Warning: uv not available, skipping graphify" >&2
  fi
fi

# ---- Install GSD-Core ----
GSD_VERSION="1.5.0"
if command -v gsd &>/dev/null; then
  echo "  GSD-Core: already installed ($(gsd --version 2>/dev/null || echo 'unknown'))"
elif command -v npx &>/dev/null; then
  echo "  GSD-Core: installing via npx..."
  npx "@opengsd/gsd-core@${GSD_VERSION}" --opencode --global || {
    echo "  Warning: GSD-Core install failed" >&2
  }
else
  echo "  Warning: npx not found — GSD-Core not installed" >&2
fi

# ---- Record version ----
echo "$VERSION" > "$HOME/.autonomous-version"
echo "Autonomous profile v$VERSION installed successfully"
