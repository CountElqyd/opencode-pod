#!/usr/bin/env bash
# Rebuilds swarm.tar.gz from source files in src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/swarm.tar.gz"

if [ ! -d "$SRC_DIR" ]; then
  echo "Error: src/ directory not found at $SRC_DIR" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/VERSION" ]; then
  echo "Error: VERSION file not found at $SCRIPT_DIR/VERSION" >&2
  exit 1
fi

echo "Building Swarm profile v$(cat "$SCRIPT_DIR/VERSION")..."
tar cf - --sort=name --owner=0 --group=0 --mtime="@0" \
  -C "$SRC_DIR" config/ \
  -C "$SCRIPT_DIR" VERSION | gzip -n > "$OUTPUT"

echo "Created: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
