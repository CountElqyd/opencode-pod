# Changelog

## [0.4.2] - 2026-08-15

### Bug Fixes
- Profile install/update: the 0.4.1 staging change extracted the profile tarball inside the container (`tar xzf - -C`), but every profile's `setup.sh` expects `$SCRIPT_DIR/<name>.tar.gz` to exist — installs failed with `Error: /tmp/.opencode-profile-<name>/<name>.tar.gz not found`. The tarball is staged as a file again (streamed via stdin as the container user, preserving the 0.4.1 ownership fix); `setup.sh` extracts it itself

## [0.4.1] - 2026-08-15

### Features
- `opencode-pod list`: shows all opencode-pod containers (name, state, project, `[orphan]` markers); `destroy` now works in directories without an `opencode-pod.toml`
- Autonomous profile: graphify workflow — `/new-project` and `/setup-project` commands, graphify + context-management skills, graphify plugin
- Profile installs write a `PROFILE-<name>.md` guide to `/workspace`; profile versions bumped (ralph 0.2.3, swarm 0.1.1, autonomous 0.2.4)

### Bug Fixes
- Profile install/update: staging via `podman cp` left root-owned files the container user cannot chmod (EPERM) or remove (EACCES) — every install reported failure after a successful setup. Files are now streamed into the container as the target user (no `chmod`, no `podman cp`, no capability dependency), with a root pre-cleanup that self-heals stale staging dirs
- Profile install/update: `podman exec` user parameterized (`CONTAINER_USER`), no longer hardcoded `-u dev`
- `destroy` in a directory without an `opencode-pod.toml` previously failed; it now works (and `list` shows `[orphan]` containers)

### Documentation
- README: profile install guide (prereqs, quick start, built-in profile table, `list` vs `profile list`); known-issues entries for the EPERM/EACCES fix

## [0.4.0] - 2026-08-12

### Features
- Autonomous profile: lean zero-interruption execution profile — GSD-Core 1.5.0, Graphify, curated superpowers skills (systematic-debugging, verification-before-completion, requesting-code-review, self-consistency-reasoner)
- `/autocode` command replacing `/launch-ralph`, with `autocode-runner` primary agent and `autocode-decider` subagent
- Declarative `toml` profile requirements: profiles can require `opencode-pod.toml` values via a `toml` block in `profile.json`; `install`/`update` diff against active config, prompt once, then apply (destroying + recreating the container)
- Bounded line-based TOML patcher that preserves comments and sibling lines

### Security
- Autonomous profile: hardened `opencode.json` permission schema and bash deny list
- TOML requirement validation against a v1 allowlist (`network.mode`, `mounts.extra`, `container.packages`, `env.*`) — scalar strings only; env keys restricted to bare identifiers; control characters rejected

### Bug Fixes
- opencode pinned to 1.18.16 in bootstrap
- Profile build fails when the profile is missing from the index
- TOML requirement apply: survives `set -euo pipefail`, correct exit-code handling in `install`/`update`, reinstalls profile after recreate wipes the home volume, forces config refresh before recreating the container
- Autonomous profile: `/autocode` pinned to `autocode-runner`, invalid `model: inherit` dropped, skills count corrected, graphify install hardened

### Refactoring
- `install`/`update` routed through the TOML requirements engine

### Tests
- Autonomous: index-tarball sha256 + VERSION consistency, gsd-config pre-seed alignment
- Profiles: clean error output for malformed TOML requirements

### Documentation
- `README.md` + `profiles/README.md` document the TOML requirements feature; profile metadata release workflow recorded

## [0.3.1] - 2026-07-24

### Security
- Profile tarball integrity: SHA256 checksum verification against `profiles/index.json` before container copy
- OpenCode version pinning: npm install pinned to `SCRIPT_VERSION` (was unpinned `latest`)
- Bootstrap race condition: atomic `mkdir` lock prevents concurrent `setup`/`start` from corrupting bootstrap state

### Bug Fixes
- Hardcoded `/home/dev` paths replaced with dynamic `CONTAINER_USER` throughout bootstrap (defaults to `dev`)
- Cross-module guard: `container_destroy` checks for `_profile_registry_path` existence before calling
- `opencode_config_path()` in `security.sh` now accepts a username parameter
- Profile install test updated for host-side download + checksum verification flow

### Documentation
- `known-issues.md`: 7 documented recurring errors with causes and fixes
- `project-map.md`: codebase structure, key file purposes, and critical constraints for cross-session orientation

## [0.3.0] - 2026-07-23

### Features
- Swarm profile: verification-gated, architect-led multi-agent development
- `--version` flag on CLI
- Profile install/update runs setup automatically inside the container
- Profile version tracking with diff, rollback, and state registry
- Release automation: release.sh, git-cliff changelog generation, GitHub Release workflow

### Bug Fixes
- Ralph profile: fabric MCP installation, uv package management, PATH setup
- Home volume ownership detection fix for Podman 6.0.1
- Container destroy now updates profile registry
- CI: reproducible tarballs, checkout@v4, shellcheck via apt

### Documentation
- AGENTS.md with version-sync reminder
- README credits, badges, accurate command descriptions

## [0.2.0] - 2026-07-13

### Features
- `profile` subcommand with 4 operations: list, info, install, update
- Reusable environment profiles system (`profiles/<name>/` convention)
- Ralph profile: bundles GSD-Core, G-Stack skills, and fabric-mcp server
- Profile index served from GitHub fetched at runtime
- Host network mode prompt for profiles that need local LLM access
- 78 new bats tests for profile subcommands and ralph profile

### CI
- Profile tarball freshness check on push/PR — stale tarballs fail CI

## [0.1.0] - 2026-07-07

Initial release.

### Features
- 8 CLI commands: init, start, setup, stop, destroy, status, doctor, upgrade
- Per-project TOML configuration with mtime-based caching
- Auto-detects Node.js, Python, Rust, Go projects
- 6-layer security model (rootless, cap-drop=ALL, no-new-privileges, filesystem boundaries, SSH isolation, API token isolation)
- Wolfi (glibc) base images (~3MB)
- Bootstrap checkpointing with resume on restart
- nvm + Node.js LTS as default runtime
- fix_home_ownership via podman unshare
- Self-downloading installer (curl | sh)
- 78 unit tests + 3 integration tests, shellcheck + CI

### Supported Distros
- Arch Linux, Fedora, Ubuntu/Debian

### Requirements
- Podman 4.3+ (rootless), Bash 4+, Linux
