# Versioning, Branching & Release Process

## Versioning Scheme

SemVer `0.x.y` (pre-1.0 development).

| Change | Bump | Example |
|--------|------|---------|
| New feature or profile | Minor | `0.2.0` → `0.3.0` |
| Bugfix or doc-only change | Patch | `0.3.0` → `0.3.1` |
| Breaking CLI change | Minor (or `1.0.0`) | `0.3.0` → `0.4.0` |

Canonical version sources: `VERSION` (repo root) and `SCRIPT_VERSION` in `opencode-pod` line 7.

Profile versions in `profiles/index.json` remain independent.

## Bump Decision Guide

- **Patch** — bug fix, docs, refactor, CI, test, chore, style, perf.
- **Minor** — new feature, subcommand, profile, flag. At `0.x.y`, breaking changes also minor.
- Tiebreaker: "Would a user who upgraded silently be surprised?"

## Conventional Commits

Every commit follows `<type>(<scope>): <description>`.

| Type | Changelog section | Bump |
|---|---|---|
| `feat` | Features | minor |
| `fix` | Bug Fixes | patch |
| `docs` | Documentation | patch |
| `refactor` | Code Refactoring | patch |
| `perf` | Performance | patch |
| `test` | Tests | patch |
| `ci` | CI/CD | patch |
| `chore` | Maintenance | patch |

Breaking changes: `feat!:` or `fix!:` — always a minor bump (or major after 1.0).

Scopes: `cli`, `profile`, `security`, `installer`, `docs`, `ci`.

## Branching Model

Trunk-based (GitHub Flow):
```
feature/my-thing → PR → main
                          ↓ tag v0.3.0
```

- Every commit on `main` passes CI.
- Feature branches are short-lived.
- Release = `git tag v<semver>` on main.
- No `develop`, no `release/` branches.

## Release Tooling

**`scripts/release.sh <version>`** — local release command:
1. Validates SemVer format, clean working tree.
2. Updates `VERSION` + `SCRIPT_VERSION`.
3. Runs `git-cliff -u` to draft changelog from commits since last tag.
4. Opens `$EDITOR` to curate into `CHANGELOG.md`.
5. Commits as `chore: release v<version>`.
6. Creates annotated tag `v<version>`.

**`cliff.toml`** — git-cliff config parsing Conventional Commits.

**`.github/workflows/release.yml`** — triggers on `v*` tag push:
- Runs tests, creates GitHub Release with changelog entry.

**`scripts/validate-version.sh`** — CI check: VERSION == SCRIPT_VERSION, valid SemVer.

## Changelog (Hybrid)

Auto-draft from commits via git-cliff, human-curated before release commit.

## Files

- `.gitignore`: `docs/` → `docs/superpowers/tmp/`
- `CONTRIBUTING.md`: Updated with CC, release process
- `docs/versioning.md`: Removed
- `scripts/release.sh`: Created
- `scripts/validate-version.sh`: Created
- `cliff.toml`: Created
- `.github/workflows/release.yml`: Created
