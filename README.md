# opencode-pod

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.2.0-blue)](VERSION)
[![Tests](https://img.shields.io/github/actions/workflow/status/CountElqyd/opencode-pod/test.yml?branch=main&label=tests)](https://github.com/CountElqyd/opencode-pod/actions)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Podman](https://img.shields.io/badge/podman-%3E%3D4.3-892CA0?logo=podman)](https://podman.io)

**Secure, disposable dev containers for the [OpenCode](https://opencode.ai) autonomous coding agent. Rootless Podman, one command, zero host access.**

```sh
# Install the latest version (one-time). See below to uninstall.
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install.sh | sh

# Start coding in any project
cd my-project && opencode-pod start
```

```sh
# Uninstall (removes CLI, containers, volumes, and Wolfi image)
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/uninstall.sh | sh
```

First run auto-detects your project type (Node, Python, Rust, Go), pulls a Wolfi base image, provisions the toolchain, generates SSH keys, and installs OpenCode — ~60s. After that, `start` is instant.

**Why a container?** OpenCode reads, edits, and runs commands on your machine. Without a container, the agent has access to your SSH keys, API tokens, home directory, and every file on disk. `opencode-pod` locks the agent into a rootless Podman container where:

- Only `$PWD` is visible — no host filesystem access
- SSH keys are per-container, never touching `~/.ssh`
- API tokens live on an isolated volume the agent can use but not read
- Network can be locked to `none` mode for offline workloads

---

## Usage

Each project gets a rootless Podman container with a persistent home volume. Your project directory is mounted at `/workspace`. The container survives shell exit — `start` reattaches instantly.

| Action | Command | Notes |
|--------|---------|-------|
| Create a config | `opencode-pod init` | Generates `opencode-pod.toml`, offline/instant |
| Provision the container | `opencode-pod setup` | One-time, ~60s. `--force-recreate` to rebuild |
| Enter the sandbox | `opencode-pod start` | Instant after setup. Runs setup first if needed |
| Suspend (preserve tools) | `opencode-pod stop` | Container pauses, home volume intact |
| Resume a stopped project | `opencode-pod start` | Same command — idempotent |
| Check current container state | `opencode-pod status` | Shows container name, state, project path, image |
| Health check + diagnostics | `opencode-pod doctor` | Checks Podman, rootless mode, image, disk space |
| Refresh tools | `opencode-pod upgrade` | Pulls fresh image if 30+ days old, syncs missing packages from config |
| Manage environment profiles | `opencode-pod profile list\|info\|install\|update <name>` | Fetch/share reusable configs |
| Wipe everything | `opencode-pod destroy` | Removes container + home volume |

### Container Lifecycle

```
init ─→ setup ─→ start ─→ [work] ─→ stop
                         ↑            │
                         └──── start ──┘
                                    → destroy (wipe all)
```

Setup is checkpointed — if interrupted, re-running resumes from the last completed step.

---

## Profiles

When no config exists, `opencode-pod start` auto-detects your project type and installs the right toolchain:

| Detected file | Profile | Packages |
|---------------|---------|----------|
| `package.json` | Node.js | `nodejs`, `npm`, `git`, `openssh` |
| `pyproject.toml` / `requirements.txt` | Python | `python3`, `uv`, `git`, `openssh` |
| `Cargo.toml` | Rust | `rust`, `cargo`, `git`, `openssh` |
| `go.mod` | Go | `go`, `git`, `openssh` |
| *(none)* | Default | `git`, `openssh`, `curl` |

All profiles include `zsh`, `bash`, `vim`, and `libstdc++`.

### Reusable Environment Profiles

Share and install pre-packaged OpenCode environments (skills, agents, config, tooling) from the project's GitHub repo:

```sh
opencode-pod profile list                 # list available profiles
opencode-pod profile info ralph           # show details
opencode-pod profile install ralph        # download + install inside container
opencode-pod profile update ralph         # re-download latest
```

`install` and `update` fetch the profile from GitHub and run setup inside the container automatically. Profiles can be committed to your repo (pinning a version for the team) or gitignored (each developer installs independently). See [`profiles/README.md`](profiles/README.md) for the convention and how to create custom profiles.

---

## Security

Six-layer isolation designed for autonomous agent containment:

**1. Rootless Podman** — Container runs as the host user. No `--privileged`, no root escalation path.

**2. Container Hardening** — `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--userns=keep-id`. Zero capabilities, no privilege escalation.

**3. Filesystem Boundaries** — Only `$PWD` bind-mounted at `/workspace` (`:Z` for SELinux). Container home on a named Podman volume — zero host filesystem visibility. Extra mounts are explicit, user-approved.

**4. SSH Isolation** — Fresh ed25519 keypair generated inside each container. Host `~/.ssh` is invisible. A compromised container exposes only ephemeral container keys.

**5. API Token Isolation** — OpenCode's `auth.json` lives on the container's home volume. The bundled `opencode.json` permission rules deny the agent read/edit access to the token file, SSH keys, AWS creds, `.env`, and `*.pem`/`*.key` files. OpenCode itself can still use the token for LLM calls.

**6. Network Isolation** — Defaults to rootless NAT (bridge). Can be locked to `none` for offline workloads or `host` for local LLM access. Port forwarding binds to `127.0.0.1`.

---

## Configuration

```toml
# opencode-pod.toml
[container]
# name = "my-api"              # optional; defaults to directory name
image = "cgr.dev/chainguard/wolfi-base:latest"  # any OCI image
packages = ["nodejs", "npm", "git", "openssh"]  # apk packages to install
user = "dev"                   # container user created on first launch

[mounts]
extra = ["~/.npmrc:/home/dev/.npmrc:ro"]   # host:container[:ro]

[env]
NODE_ENV = "development"       # any key=value pairs

[network]
mode = "bridge"                # "bridge" (internet), "none" (isolated), or "host"
forward = [3000, 8080]         # ports accessible from host

[security]
http = false                   # true = allow HTTP, false = HTTPS-only
harden = true                  # enable seccomp, cap-drop, no-new-privileges
```

See `example/opencode-pod.toml` for a fully annotated reference.

---

## FAQ

**How is this different from `podman run -it`?**  
`opencode-pod` automates image pull, user creation, SSH key generation, OpenCode install, permission rules, and checkpointed bootstrap. `podman run -it` leaves all of that to you.

**Can I use this without OpenCode?**  
Yes — the container is a functional dev sandbox with auto-detected toolchains and SSH keys. OpenCode is installed during setup, but you never have to run it.

**Does this work with Docker instead of Podman?**  
No. It's Podman-specific (rootless, daemonless, user-namespace isolation). Docker requires a daemon and `sudo`.

**What about VS Code devcontainers?**  
Different trade-off. Devcontainers give you IDE integration and Dockerfiles. `opencode-pod` gives you agent-specific hardening (API token isolation, deny rules) and instant `start`/`stop` with no daemon.

**Can I share container setups with my team?**  
Yes. Commit the `opencode-pod.toml` and optionally pin reusable profiles in `profiles/`. Everyone gets identical environments.

**Container was destroyed — did I lose my work?**  
No. Source code lives on the host at `$PWD`. Only the container home volume (tools, SSH keys, config) is lost. Re-run `setup` to recreate.

---

## Requirements

- **Podman 4.3+** (rootless) — [install guide](https://podman.io/docs/installation)
- **Bash 4+**
- **No sudo needed** — everything runs rootless

| OS | Status |
|----|--------|
| Linux | Fully supported — tested on Arch, Fedora, Ubuntu/Debian |
| Windows | Supported via **WSL2** (install Podman inside the WSL2 distro) |
| macOS | Not natively supported — use Podman machine or a Linux VM |

---

## Acknowledgments

This project builds on the work of several open-source projects and communities:

- **[OpenCode Swarm](https://github.com/ZaxbyHub/opencode-swarm)** — Architect-centric agentic swarm plugin for OpenCode with hub-and-spoke orchestration, SME consultation, code generation, and QA review
- **[gstack](https://github.com/garrytan/gstack)** — Garry Tan's opinionated AI agent toolkit (23 specialist skills acting as CEO, designer, eng manager, QA, and release engineer) for Claude Code and other agents
- **[GSD (Git. Ship. Done.)](https://github.com/open-gsd/gsd-core)** — Lightweight meta-prompting, context-engineering, and spec-driven development system
- **[fabric](https://github.com/danielmiessler/fabric)** — AI-powered analysis patterns by Daniel Miessler
- **[superpowers](https://github.com/obra/superpowers)** — Agent skill ecosystem by Obra
- **[Podman](https://podman.io)** — Rootless container engine
- **[OpenCode](https://opencode.ai)** — Autonomous coding agent

---

## License

MIT
