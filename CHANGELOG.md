# Changelog

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
