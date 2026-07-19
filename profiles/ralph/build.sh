#!/usr/bin/env bash
# Rebuilds ralph.tar.gz from source files in src/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT="$SCRIPT_DIR/ralph.tar.gz"
INDEX="$SCRIPT_DIR/../index.json"

NAME="$(basename "$SCRIPT_DIR")"
VERSION=$(python3 -c "
import sys, json
data = json.load(open('$INDEX'))
for p in data.get('profiles', []):
    if p.get('name') == '$NAME':
        print(p.get('version', '0.0.0'))
" 2>/dev/null || echo "0.0.0")

echo "Building Ralph profile v$VERSION..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
echo "$VERSION" > "$TMPDIR/VERSION"

tar cf - --sort=name --owner=0 --group=0 --mtime="@0" \
  -C "$SRC_DIR" config/ skills/ agents/ commands/ fabric-mcp/ gsd-core/ \
  -C "$TMPDIR" VERSION | gzip -n > "$OUTPUT"

echo "Created: $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
