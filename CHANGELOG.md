# Changelog

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
