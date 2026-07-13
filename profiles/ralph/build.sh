#!/usr/bin/env bash
# Rebuilds ralph.tar.gz from source files in src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/ralph.tar.gz"

if [ ! -d "$SRC_DIR" ]; then
  echo "Error: src/ directory not found at $SRC_DIR" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/VERSION" ]; then
  echo "Error: VERSION file not found at $SCRIPT_DIR/VERSION" >&2
  exit 1
fi

echo "Building Ralph profile v$(cat "$SCRIPT_DIR/VERSION")..."
tar czf "$OUTPUT" \
  --sort=name --owner=0 --group=0 \
  -C "$SRC_DIR" config/ skills/ agents/ commands/ fabric-mcp/ gsd-core/ \
  -C "$SCRIPT_DIR" VERSION

echo "Created: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
