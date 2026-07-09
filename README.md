# opencode-pod

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](VERSION)
[![Tests](https://img.shields.io/github/actions/workflow/status/CountElqyd/opencode-pod/test.yml?branch=main&label=tests)](https://github.com/CountElqyd/opencode-pod/actions)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Podman](https://img.shields.io/badge/podman-%3E%3D4.3-892CA0?logo=podman)](https://podman.io)

**Secure, disposable dev containers for the [OpenCode](https://opencode.ai) autonomous coding agent.**

---

## Table of Contents

- [What is opencode-pod?](#what-is-opencode-pod)
- [Why this exists for OpenCode](#why-this-exists-for-opencode)
- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [All Commands](#all-commands)
- [Auto-Detection Profiles](#auto-detection-profiles)
- [Security](#security)
- [Configuration](#configuration)
- [Error Recovery](#error-recovery)
- [Requirements](#requirements)
- [Development](#development)
- [License](#license)

---

## What is opencode-pod?

A single Bash script that creates **per-project, rootless Podman containers** sandboxed from your host. Purpose-built for [OpenCode](https://opencode.ai) — the AI coding agent that runs on your machine and has access to your filesystem, SSH keys, API tokens, and personal data.

Instead of letting the agent roam free on your host, `opencode-pod` gives it a locked-down container with:

- Zero host filesystem visibility (only `$PWD` mounted)
- A fresh SSH key pair (never touches `~/.ssh`)
- Isolated API tokens (agent can use them, cannot read them)
- Auto-detected toolchains (Node, Python, Rust, Go)
- One-command startup and teardown

---

## Why this exists for OpenCode

OpenCode is an autonomous agent — it reads, edits, runs shell commands, and manages files. On your host, that means it has access to everything you do. `opencode-pod` solves this by running OpenCode **inside** a container where:

- The agent's `read`/`edit` permissions are scoped to `/workspace` (your project)
- `auth.json` lives on an isolated volume — the agent cannot read or edit it
- SSH keys are container-scoped — host keys are invisible
- `curl` and `wget` can be blocked at the OpenCode permission level
- Port forwarding binds to `127.0.0.1` — no external network access

It's the difference between "OpenCode on your laptop" and "OpenCode in a locked room with only what it needs."

---

## Quick Start

```sh
# One-time install
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install.sh | sh

# Enter any project
cd my-project
opencode-pod start
```

First run auto-detects your project type, pulls a Wolfi image, installs packages,
sets up Node.js (via nvm), generates SSH keys, and installs OpenCode — all in ~60s.

After setup, `start` is instant. Work inside the container, then `exit` — the
container keeps running. Re-enter anytime with `opencode-pod start`.

```sh
# When you're done
opencode-pod stop       # suspend, preserve tools
opencode-pod destroy    # wipe container + volume
```

---

## How It Works

### Lifecycle

```
┌──────┐    ┌───────┐    ┌───────┐    ┌─────────┐    ┌─────────┐
│ init │───▶│ setup │───▶│ start │───▶│  work   │───▶│  stop   │
└──────┘    └───────┘    └───────┘    │(exit)   │    └─────────┘
                                      └─────────┘         │
                                           │              │
                                           ▼              ▼
                                     ┌─────────┐    ┌───────────┐
                                     │  start  │    │  destroy  │
                                     │(resume) │    │(wipe all) │
                                     └─────────┘    └───────────┘
```

### Container Naming

Containers are named `opencode-pod-<dirname>-<6char-path-hash>`. The 6-char hash is
derived from SHA256 of the absolute project path, preventing collisions between
directories with the same name in different locations.

### Bootstrap Checkpoints

Setup is checkpointed — if it fails mid-way (network issue, power loss), re-running
resumes from the last completed step:

1. **fix_home_ownership** — `podman unshare chown` the home volume
2. **packages_installed** — `apk add` with per-package verification via `apk info -e`
3. **user_created** — creates `dev` user (UID 1000) with zsh
4. **ssh_key_generated** — fresh ed25519 keypair inside the container
5. **nvm_installed** — nvm v0.40.3 + Node.js LTS, `.zshenv` configured
6. **opencode_config_copied** — `opencode.json` permission rules deployed
7. **opencode_installed** — `npm install -g opencode-ai`

### Package Verification

The tool does not trust `apk add`'s exit code (which can be non-zero due to
triggers or post-install warnings). Every package is individually verified with
`apk info -e <pkg>`.

---

## All Commands

| When you want to...              | Run                       | Notes                                         |
|----------------------------------|---------------------------|-----------------------------------------------|
| Create a config                  | `opencode-pod init`       | Generates `opencode-pod.toml`, offline/instant |
| Pull image + provision container | `opencode-pod setup`      | One-time, ~60s. `--force-recreate` to rebuild  |
| Enter the sandbox                | `opencode-pod start`      | Instant after setup. Runs setup if needed      |
| Stop and save work for later     | `opencode-pod stop`       | Preserves installed tools                     |
| Resume a stopped project         | `opencode-pod start`      | Same command — idempotent                      |
| Check which containers are alive | `opencode-pod status`     | Shows state, project path, image               |
| Health check your setup          | `opencode-pod doctor`     | Checks Podman, image, SELinux, disk space. `--fix` |
| Update tools in the container    | `opencode-pod upgrade`    | Checks image freshness (30-day). `--pull` to refresh |
| Destroy everything, start fresh  | `opencode-pod destroy`    | Removes container + home volume               |

---

## Auto-Detection Profiles

When no TOML config exists, `opencode-pod start` detects your project type and
installs the appropriate toolchain:

| Detected file           | Profile   | Packages installed                          |
|-------------------------|-----------|----------------------------------------------|
| `package.json`          | Node.js   | `nodejs`, `npm`, `git`, `openssh`            |
| `pyproject.toml` or `requirements.txt` | Python | `python3`, `uv`, `git`, `openssh`  |
| `Cargo.toml`            | Rust      | `rust`, `cargo`, `git`, `openssh`            |
| `go.mod`                | Go        | `go`, `git`, `openssh`                       |
| *(none detected)*       | Default   | `git`, `openssh`, `curl`                     |

All profiles also include `zsh`, `bash`, `vim`, and `libstdc++` as base packages.

---

## Security

Six-layer isolation model designed for autonomous agent containment.

### 1. Rootless Podman
Container runs as the host user. `--privileged` is never used. User namespace maps
"container root" to the host user — a compromised container cannot escalate to host root.

### 2. Container Hardening
- `--cap-drop=ALL` — zero capabilities (not even CAP_CHOWN)
- `--security-opt=no-new-privileges` — no privilege escalation
- `--userns=keep-id` — keep the host user's UID inside
- No host PID namespace, no host `/proc`

### 3. Filesystem Boundaries
- Only `$PWD` bind-mounted at `/workspace` (with `:Z` for SELinux)
- Container home lives on a named Podman volume — zero host filesystem visibility
- Extra mounts are explicit and user-approved in config

### 4. SSH Isolation
- Fresh ed25519 keypair generated inside the container on first launch
- Separate key per container — host `~/.ssh` is invisible
- Compromised container exposes only ephemeral container keys

### 5. API Token Isolation
- OpenCode `auth.json` lives on the container's home volume (Podman volume)
- `opencode.json` permission rules block agent-level read/edit access to the token
- OpenCode itself can still use the token for LLM API calls
- Agent cannot `curl`/`wget` the token out (blocked at permission level)

### 6. Network Isolation
- Full internet via rootless slirp4netns/pasta NAT
- Container **cannot access host network** directly
- Port forwarding binds to `127.0.0.1` only (not `0.0.0.0`)
- Configurable to `none` mode for zero-network isolation

### OpenCode Permission Rules

The bundled `opencode.json` deploys these deny rules inside the container:

| Permission | Blocked paths / commands     |
|------------|------------------------------|
| `read`     | `auth.json`, `~/.ssh/*`, `~/.aws/*`, `*.pem`, `*.key`, `.env` |
| `edit`     | `auth.json`, `~/.ssh/*`, `~/.aws/*`, `*.pem`, `*.key`, `.env` |
| `bash`     | `curl`, `wget`               |

---

## Configuration

Create a per-project config with `opencode-pod init`, then customize:

```toml
# opencode-pod.toml
[container]
name = "my-api"                        # optional, overrides dirname
image = "cgr.dev/chainguard/wolfi-base:latest"
packages = ["nodejs", "npm", "git", "openssh"]
user = "dev"

[mounts]
extra = ["~/.npmrc:/home/dev/.npmrc:ro"]

[env]
NODE_ENV = "development"

[network]
mode = "bridge"                        # "bridge" or "none"
forward = [3000, 8080]

[security]
http = false                           # HTTPS-only at opencode level
harden = true                          # seccomp, cap-drop, no-new-privileges
```

See `example/opencode-pod.toml` for a fully annotated reference.

---

## Error Recovery

When things go wrong, `opencode-pod doctor` is your first step. Specific errors
have specific fixes:

| Problem                       | Likely cause               | Fix                                      |
|-------------------------------|----------------------------|------------------------------------------|
| `podman: command not found`    | Podman not installed       | Run OS-specific install command printed  |
| `image pull failed`           | Network or registry issue  | Check internet connectivity              |
| `address already in use`      | Port conflict              | Change ports in config or free the port  |
| `no space left on device`     | Disk full                  | `podman system prune`, clean old images  |
| SELinux denial in logs        | SELinux context            | `restorecon -Rv /path/to/project`        |
| `subuid/subgid not configured`| User namespace not set     | Run `opencode-pod doctor` for instructions |
| APK network/unreachable       | Container network issue    | `opencode-pod doctor` to verify networking|
| APK package not found / 404   | Wrong package name         | Check spelling, search Wolfi packages    |

Bootstrap checkpoints also protect against partial failures — if setup is
interrupted, re-running resumes from the last checkpoint rather than starting over.

---

## Requirements

- **Podman 4.3+** (rootless) — [install guide](https://podman.io/docs/installation)
- **Bash 4+**
- **No sudo needed** — everything runs rootless

### OS Compatibility

| OS      | Status                        |
|---------|-------------------------------|
| Linux   | Fully supported (primary target) — tested on Arch, Fedora, Ubuntu/Debian |
| Windows | Supported via **WSL2** (install Podman inside the WSL2 distro) |
| macOS   | Not natively supported — use Podman machine or a Linux VM |

---

## Development

### Test Suite

78 unit tests + 3 integration tests using [bats](https://github.com/bats-core/bats-core):

```sh
# Run all tests
bats bats/*.bats

# Run with TAP output
bats --formatter tap bats/*.bats
```

Integration tests require a running Podman and are skipped automatically when
Podman is unavailable or when running in CI without `PODMAN_INTEGRATION=1`.

### CI

GitHub Actions runs `shellcheck` on every script plus the full bats test suite
on push and PR.

### Structure

```
opencode-pod          # main CLI entry point (287 lines)
lib/
  toml.sh             # TOML parser with mtime-based caching
  distro.sh           # OS detection (Arch/Fedora/Ubuntu)
  podman.sh           # Core lifecycle: create, setup, start, stop, destroy, bootstrap
  security.sh         # Hardening flags, opencode config path
defaults/             # Default config template
example/              # Annotated example configs
bats/                 # Test files
docs/                 # Additional documentation
```

---

## License

MIT
