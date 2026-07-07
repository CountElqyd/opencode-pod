# opencode-pod

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](VERSION)
[![Tests](https://img.shields.io/github/actions/workflow/status/CountElqyd/opencode-pod/test.yml?branch=main&label=tests)](https://github.com/CountElqyd/opencode-pod/actions)
[![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash)](https://www.gnu.org/software/bash/)
[![Podman](https://img.shields.io/badge/podman-%3E%3D4.3-892CA0?logo=podman)](https://podman.io)

Secure, disposable dev containers for autonomous coding agents. Rootless Podman, Wolfi images, one command to start.

---

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install.sh | sh
```

---

## Quick Start

```sh
cd my-project
opencode-pod start
# ...work inside the sandbox...
exit       # container keeps running in background
```

---

## Common Workflows

| When you want to...              | Run                       |
|----------------------------------|---------------------------|
| Start a project in a sandbox     | `opencode-pod start`      |
| Stop and save work for later     | `opencode-pod stop`       |
| Resume a stopped project         | `opencode-pod start`      |
| Check which containers are alive | `opencode-pod status`     |
| Update tools in the container    | `opencode-pod upgrade`    |
| Destroy everything, start fresh  | `opencode-pod destroy`    |
| Health check your setup          | `opencode-pod doctor`     |
| Create a custom config           | `opencode-pod init`       |

---

## Config (optional)

```toml
# opencode-pod.toml
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
packages = ["git", "openssh", "curl"]
user = "dev"

[network]
mode = "bridge"
forward = [3000, 8080]

[security]
harden = true
```

---

## Security

Six-layer model:
1. Rootless Podman — container runs as host user
2. Hardening — `--cap-drop=ALL`, `--no-new-privileges`
3. Filesystem — only `$PWD` mounted at `/workspace`
4. SSH isolation — per-container key, host keys invisible
5. API token isolation — opencode permission rules
6. Network — bridge or none mode

---

## Requirements

- Podman 4.3+ (rootless)
- Bash 4+
- Linux (Arch, Fedora, Ubuntu/Debian)

## License

MIT
