#!/usr/bin/env bash
set -euo pipefail

errors=0
version_file="$(cat VERSION)"
script_version="$(sed -n 's/^SCRIPT_VERSION="\(.*\)"$/\1/p' opencode-pod)"

if [ "$version_file" != "$script_version" ]; then
  echo "ERROR: VERSION file ($version_file) != SCRIPT_VERSION ($script_version)"
  errors=1
fi

if ! echo "$version_file" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: VERSION file does not contain valid SemVer (got: $version_file)"
  errors=1
fi

exit $errors
