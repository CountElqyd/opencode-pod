# opencode-pod

Secure, disposable dev containers for OpenCode-based autonomous coding agents. Rootless Podman, Wolfi images, one command to start.

## Quick Start

```sh
curl -fsSL https://raw.githubusercontent.com/.../main/install.sh | sh
```

Then in any project directory:

```sh
opencode-pod start
```

## Commands

| Command | Description |
|---------|-------------|
| `opencode-pod init` | Create opencode-pod.toml (interactive) |
| `opencode-pod start` | Build + start container, drop into zsh |
| `opencode-pod stop` | Stop container, preserve installed tools |
| `opencode-pod shell` | Open new shell into running container |
| `opencode-pod destroy` | Remove container + home volume |
| `opencode-pod status` | Show container state, project path |
| `opencode-pod logs` | Show container output, --follow for live tail |
| `opencode-pod doctor` | Health check: podman, image, SELinux, disk space |
| `opencode-pod upgrade` | Check base image freshness, install new packages |

## Config

```toml
# opencode-pod.toml
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
packages = ["nodejs", "npm", "git", "openssh"]
user = "dev"

[network]
mode = "bridge"       # "bridge" or "none"
forward = [3000, 8080]

[security]
harden = true
```

## Security

Six-layer security model:
1. Rootless Podman — container runs as host user, no root
2. Container hardening — cap-drop=ALL, no-new-privileges
3. Filesystem boundaries — only $PWD mounted at /workspace
4. SSH isolation — per-container key, host keys invisible
5. API token isolation — opencode permission rules
6. Network — bridge or none mode

## Requirements

- Podman 4.3+ (rootless)
- Bash 4+
- Linux (Arch, Fedora, Ubuntu/Debian)

## License

MIT
