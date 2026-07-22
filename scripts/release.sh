#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [ -z "$version" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.3.0"
  exit 1
fi

if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: version must be SemVer (e.g. 0.3.0)"
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is dirty. Commit or stash first."
  exit 1
fi

echo "==> Updating VERSION file"
echo "$version" > VERSION

echo "==> Updating SCRIPT_VERSION in opencode-pod"
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s/^SCRIPT_VERSION=\".*\"$/SCRIPT_VERSION=\"$version\"/" opencode-pod
else
  sed -i "s/^SCRIPT_VERSION=\".*\"$/SCRIPT_VERSION=\"$version\"/" opencode-pod
fi

if [ -z "${RELEASE_DRY_RUN:-}" ]; then
  echo "==> Generating changelog draft"
  if command -v git-cliff &>/dev/null; then
    changedir=$(mktemp -d)
    git cliff -u --unreleased > "$changedir/new-changelog.md"
    echo "Changelog draft written to $changedir/new-changelog.md"
    echo "Edit it, then paste the result into CHANGELOG.md under a ## [$version] - $(date +%F) header."
    echo "When done, press enter to continue..."
    read -r
    echo "Opening changelog for manual edit..."
    ${EDITOR:-vi} CHANGELOG.md
  else
    echo "git-cliff not found. Install it or manually write the changelog entry."
    echo "See: https://github.com/orhun/git-cliff"
    echo "Press enter when CHANGELOG.md is ready..."
    read -r
    ${EDITOR:-vi} CHANGELOG.md
  fi
else
  echo "==> [DRY RUN] Skipping changelog, commit, and tag"
fi

if [ -z "${RELEASE_DRY_RUN:-}" ]; then
  echo "==> Committing"
  git add VERSION opencode-pod CHANGELOG.md
  git commit -m "chore: release v$version"

  echo "==> Tagging"
  git tag -a "v$version" -m "v$version"
else
  echo "==> [DRY RUN] Would commit and tag v$version"
fi

echo ""
echo "Done! Review with: git log --oneline -5"
echo "Push with: git push && git push --tags"
