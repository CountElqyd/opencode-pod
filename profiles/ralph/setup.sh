#!/usr/bin/env bash
# Ralph profile installer — run inside opencode-pod container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SCRIPT_DIR/ralph.tar.gz"
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
INSTALLED=$(cat "$HOME/.ralph-version" 2>/dev/null || echo "0.0.0")

if [ "$INSTALLED" = "$VERSION" ]; then
  echo "Ralph profile v$VERSION already installed"
  exit 0
fi

echo "Installing Ralph profile v$VERSION..."

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

# ---- Install GSD-Core ----
if [ -d "$EXTRACTED/gsd-core" ]; then
  GSD_DIR="$HOME/.config/opencode/gsd-core"
  mkdir -p "$GSD_DIR"
  cp -r "$EXTRACTED/gsd-core/"* "$GSD_DIR/" 2>/dev/null
  echo "  GSD-Core: installed"
fi

# ---- Install fabric-mcp ----
if [ -d "$EXTRACTED/fabric-mcp" ]; then
  FABRIC_DIR="$HOME/.local/share/fabric-mcp"
  mkdir -p "$FABRIC_DIR"
  cp -r "$EXTRACTED/fabric-mcp/"* "$FABRIC_DIR/" 2>/dev/null
  if command -v npm &>/dev/null && [ -f "$FABRIC_DIR/package.json" ]; then
    echo "  fabric-mcp: installing dependencies..."
    (cd "$FABRIC_DIR" && npm install --silent) || {
      echo "  Warning: fabric-mcp npm install failed" >&2
      rm -f "$HOME/.ralph-version" 2>/dev/null
    }
  fi
  echo "  fabric-mcp: installed"
fi

# ---- Install fabric-ai CLI ----
if ! command -v fabric-ai &>/dev/null; then
  if ! command -v uv &>/dev/null; then
    echo "  fabric-ai: installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | UV_UNMANAGED_INSTALL="$HOME/.local" sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
  echo "  fabric-ai: installing via uv..."
  uv pip install --system fabric-ai
  echo "  fabric-ai: installed"
else
  echo "  fabric-ai: already installed"
fi

# ---- Record version ----
echo "$VERSION" > "$HOME/.ralph-version"
echo "Ralph profile v$VERSION installed successfully"
