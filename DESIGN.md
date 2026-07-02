# opencode-pod — Design Spec

Secure, disposable dev containers for OpenCode-based autonomous coding agents. Rootless Podman, Wolfi images, one command to start.

## Motivation

Autonomous AI coding agents present unique security risks. The "lethal trifecta" — access to private data, exposure to untrusted content (npm packages, dependencies), and ability to externally communicate — means a compromised package can exfiltrate SSH keys, API tokens, and project files. A containerized development environment with proper isolation boundaries contains the blast radius.

Existing options (Docker-based devcontainers, full VMs) are either daemon-heavy, complex to configure, or lack the specific hardening needed for agent-driven workflows. This tool provides the minimum viable container — rootless, hardened, per-project — that drops into a productive shell in one command.

## Requirements

- Secure isolation from host filesystem (SSH keys, API tokens, personal files)
- Rootless Podman (no daemon, no root, no `sudo`)
- Lean Wolfi base images (glibc, apk package manager)
- Per-project configuration via TOML
- Persistent container lifecycle (containers survive shell exit, re-attachable)
- Cross-distro support (Arch, Fedora, Ubuntu/Debian, macOS)
- Single shell script distribution — no build step, no runtime dependencies beyond Podman
- OpenCode-native API token isolation via permission rules

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Container engine | Rootless Podman | No daemon, user-namespace isolation, no root requirement |
| Base image | Wolfi (glibc) | Small base (~3MB), glibc avoids musl compatibility issues, apk feels familiar |
| Config format | TOML | Comments, no indentation gotchas, ecosystem convergence |
| Shell (host scripts) | bash 4+ | Available on every Linux distro by default, portable |
| Shell (container) | zsh | User preference |
| Container command | sleep infinity | Keeps container alive between exec sessions (no PID 1 exit) |
| Distribution | Shell script | Zero deps, auditable, works everywhere |
| Build approach | No Dockerfile | Create from base image, install packages on first launch |
| OpenCode install | npm install -g | No Wolfi apk available; npm is the canonical install path |
| SSH isolation | Per-container key | Generated inside container, host key never exposed |
| API token isolation | OpenCode auth + permission rules | Native OpenCode permission system blocks agent access to auth.json |
| Container lifecycle | Persistent with setup/start split | Provisioning is one-time (`setup`); shell entry is always instant (`start`). Like docker run -d, but for dev shells. |
| Package verification | apk info -e | Don't trust apk exit code; verify each package installed individually |
| Error handling | classify_error() with stderr patterns | Pattern-matches podman/apk stderr for specific fix instructions; falls back to generic error |
| Naming | Path-hash | 6-char SHA256 of full path prevents collisions between same-named dirs |
| Testing | bats | Bash Automated Testing System for unit tests; real Podman for integration tests |

## Architecture

### Project Structure

```
opencode-podman-setup/
├── LICENSE                     # MIT
├── README.md
├── CONTRIBUTING.md
├── install.sh                  # curl | bash entry point
├── opencode-pod                # main runtime command
├── bats/
│   ├── toml.bats               # TOML parser + caching tests
│   ├── distro.bats             # distro detection tests
│   ├── podman.bats             # container lifecycle, setup, error classification, bootstrap tests
│   ├── security.bats           # hardening flag verification
│   └── install.bats            # installer file placement tests
│   └── integration.bats        # real-podman tests (@slow, skipped without podman)
├── lib/
│   ├── toml.sh                 # TOML parser + mtime-based caching
│   ├── distro.sh               # OS/distro detection
│   ├── podman.sh               # container lifecycle, setup, error classification, bootstrap
│   └── security.sh             # hardening flags, opencode config path
├── defaults/
│   └── opencode-pod.toml       # default config template for init
├── example/
│   ├── opencode-pod.toml       # annotated example config
│   └── opencode.json           # example OpenCode config for container
└── .github/
    └── workflows/
        └── test.yml            # CI: shellcheck + bats tests
```

### Commands

```
opencode-pod init      # create opencode-pod.toml (offline, instant)
opencode-pod setup     # pull image, create container, run bootstrap (one-time)
opencode-pod start     # enter container shell (instant — exec into running container)
opencode-pod stop      # stop container, preserve installed tools
opencode-pod shell     # open new shell into running container
opencode-pod destroy   # remove container + home volume
opencode-pod status    # show container state, project path
opencode-pod logs      # show container output, --follow for live tail
opencode-pod doctor    # health check: podman, image, SELinux, disk space
opencode-pod upgrade   # check base image freshness, install new packages from TOML
```

### TOML Config Schema

```toml
# opencode-pod.toml

[container]
# name = "my-api"    # optional, overrides dirname-derived name
image = "cgr.dev/chainguard/wolfi-base:latest"
packages = ["nodejs", "npm", "python3", "uv", "git", "openssh"]
user = "dev"

[mounts]
extra = []      # e.g. "~/.npmrc:/home/dev/.npmrc:ro"

[env]
# FOO = "bar"

[network]
mode = "bridge"      # "bridge" or "none"
forward = [3000, 8080]

[security]
http = false        # HTTPS-only by default
harden = true       # seccomp, no-new-privileges
```

### Container Lifecycle

Containers are **persistent** — they survive shell exit and can be reattached later. The container runs `sleep infinity` as its primary process, keeping it alive indefinitely. Shell entry is via `podman exec`. Provisioning is separated from shell entry: `setup` does the one-time work, `start` is always instant.

```
opencode-pod setup
 ├── Config exists?
 │   └── no → error: "Run opencode-pod init first"
 ├── Podman installed? → no → classify_error
 ├── Wolfi image cached? → no → podman pull
 ├── Container exists?
 │   ├── running → "already set up" (idempotent, no-op)
 │   └── stopped/created → "already exists. Use start to reattach." (idempotent)
 └── no → first-time creation:
     1. podman volume create <home-volume>
     2. podman create from wolfi-base
        - named volume → /home/dev (persistent)
        - bind mount $PWD → /workspace
        - --userns=keep-id (host UID → container 1000)
        - --cap-drop=ALL --security-opt=no-new-privileges
        - command: sleep infinity (keeps container alive)
     3. podman start
     4. First-launch bootstrap (runs once, checkpointed):
        - apk add -U --no-cache <packages>
        - Verify each package via apk info -e (don't trust exit code)
        - create dev user
        - generate SSH key (~/.ssh/id_ed25519 inside container)
        - copy OpenCode config (opencode.json deny rules)
        - npm install -g @anthropic-ai/opencode
     5. Print: "Container ready. Run 'opencode-pod start' to enter."

opencode-pod start
 ├── Container running? → podman exec -it --workdir /workspace <container> zsh
 ├── Container stopped? → podman start + run_bootstrap (checkpoint) + exec into zsh
 ├── No config? → auto-detection → write config → run setup → exec into zsh
 └── No container? → error: "Container not set up. Run 'opencode-pod setup' first."

opencode-pod stop → podman stop <container> (pauses, home volume intact)
opencode-pod shell → podman exec -it --workdir /workspace <container> zsh (into running container)
opencode-pod destroy → podman rm -f <container> + podman volume rm <home-volume>
```

### Container and Volume Naming

- Container name: `opencode-pod-<dirname-or-name>-<6char-path-hash>` — 6-char SHA256 of the full project path prevents collisions between directories with the same name in different parent folders.
- Optional `[container] name = "my-api"` overrides the dirname portion.
- Home volume name: `<container-name>-home` (named Podman volume for `/home/dev` persistence).
- Container user `dev` is created with UID matching the host user's UID, enabled by `--userns=keep-id`.

### First-Launch Bootstrap with Checkpointing

The bootstrap is fragile — `apk add` can fail mid-install due to network issues, missing packages, or Wolfi repo downtime. To handle partial failures:

1. A `.bootstrap-progress` file in the container's home volume tracks each completed step (one step per line):
   - `packages_installed` — packages installed and verified via `apk info -e`
   - `user_created` — dev user exists
   - `ssh_key_generated` — `~/.ssh/id_ed25519` exists
   - `opencode_config_copied` — `~/.local/share/opencode/opencode.json` present
   - `opencode_installed` — `npm install -g @anthropic-ai/opencode` completed
2. On `setup`, if the container exists but bootstrap is incomplete:
   - Copies `.bootstrap-progress` from the container first (cross-invocation resume).
   - Re-runs skipped steps only (resume from checkpoint).
3. On `start`/reattach: runs `run_bootstrap` as a no-op safety check (all steps already done → instant return).
4. If bootstrap fails again, offer: `--force-recreate` to `destroy` + `setup` fresh.
5. `apk add` doesn't trust exit code — packages are verified individually via `apk info -e`. Trigger/post-install warnings that produce non-zero exits don't block bootstrap.

### OpenCode Installation

opencode is installed inside the container during first-launch bootstrap via npm:

```
run_bootstrap: opencode_installed step
 ├── Check: is_bootstrap_step_done "opencode_installed"?
 │    ├── done → skip
 │    └── not done → npm install -g @anthropic-ai/opencode
 ├── Success → mark_bootstrap_step "opencode_installed"
 └── Failure → completed_all=false, retry on next setup
```

**Requirements:**
- `nodejs` and `npm` must be in `[container.packages]`
- npm network error → bootstrap marks step incomplete, next `setup` retries
- Works on Wolfi's glibc base (no musl compatibility issues)
- Future: TOML could support version pinning via npm `@version` syntax

### Auto-Detection

`opencode-pod start` without a `opencode-pod.toml` config auto-detects the project type from known markers in the project directory. Falls back to interactive `init` if nothing matches.

| Marker file | Detected profile | Auto-installed packages |
|------------|-----------------|------------------------|
| `package.json` | Node.js | `nodejs`, `npm`, `git`, `openssh` |
| `pyproject.toml` or `requirements.txt` | Python | `python3`, `uv`, `git`, `openssh` |
| `Cargo.toml` | Rust | `rust`, `cargo`, `git`, `openssh` |
| `go.mod` | Go | `go`, `git`, `openssh` |
| None found | Default | `git`, `openssh`, `curl` |

Before creating the container, the detected profile is printed. User confirms or opts for interactive `init` to customize. If the user accepts, a `opencode-pod.toml` is written with the detected packages so future starts are instant.

### Upgrade Command

`opencode-pod upgrade` handles two concerns:

1. **Base image freshness:** Compares the locally cached Wolfi base image's creation date against a 30-day threshold. If stale, pulls latest and prints a warning that existing containers need `destroy` + `start` to use the new base.
2. **Package delta:** Compares `[container.packages]` in TOML against `apk list --installed` in the container. New packages are installed via `podman exec apk add`. Removed packages trigger a warning ("Package X is in TOML but wasn't found in the container — not auto-removing for safety"). No packages are auto-removed.

```
opencode-pod upgrade
    ├── Check Wolfi base image age
    │   ├── < 30 days → OK
    │   └── >= 30 days → Print "Base image is N days old. Run upgrade --pull to refresh."
    ├── Check package delta (container must be running)
    │   ├── Packages in TOML but not installed → podman exec apk add <new-packages>
    │   └── Packages installed but not in TOML → Print warning, no auto-remove
    └── Done
```

### Doctor Command

`opencode-pod doctor` runs a battery of health checks in under 15 seconds and prints PASS/FAIL per check with fix instructions. `--fix` runs safe repairs automatically.

Checks:
- Podman installed and version >= 4.3
- Rootless Podman working (subuid/subgid configured)
- XDG_RUNTIME_DIR set
- Wolfi base image present locally
- SELinux labeling functional (Linux only)
- Container mount works (fast smoke test)
- Home volume accessible
- Disk space >= 2GB for `/home/dev` volume
- Port forward ports are free

Each failure prints a fix command. Checks requiring sudo (subuid setup) are report-only even with `--fix`.

### Logs Command

`opencode-pod logs` shows the last 200 lines of container output for the current project. `--follow` tails live output. Podman captures container output for persistent containers; this reads from the Podman log driver.

```
opencode-pod logs          # last 200 lines
opencode-pod logs --follow # tail -f equivalent
opencode-pod logs -n 50    # last 50 lines
```

### Security Model

**Layer 1 — Rootless Podman:** Container runs as host user (not root), `--privileged` never used. User namespace maps "container root" → host user.

**Layer 2 — Container Hardening:** `--cap-drop=ALL`, `--security-opt=no-new-privileges`, `--userns=keep-id`. No host PID namespace, no host /proc.

**Layer 3 — Filesystem Boundaries:** Only `$PWD` bind-mounted at `/workspace` (rw). Container home on named volume — zero host filesystem visibility. Extra mounts from `[mounts.extra]` are explicit, user-approved.

**Layer 4 — SSH Isolation:** SSH key generated inside container on first launch. Separate key pair, never touches host. User adds to GitHub once manually. Host `~/.ssh` invisible to container.

**Layer 5 — API Token Isolation:** OpenCode auth.json lives inside the container's home volume at `~/.local/share/opencode/auth.json`. The container's `opencode.json` permission rules explicitly deny agent-level read access to sensitive paths:

```jsonc
// example/opencode.json — placed at ~/.local/share/opencode/opencode.json inside container
{
  "permissions": {
    "read": {
      "deny": [
        "~/.local/share/opencode/auth.json",
        "~/.ssh/*",
        "~/.aws/*",
        "*.pem",
        "*.key",
        ".env",
        "/home/dev/.local/share/opencode/auth.json"
      ]
    },
    "edit": {
      "deny": [
        "~/.ssh/*",
        "~/.aws/*",
        "*.pem",
        "*.key",
        "~/.local/share/opencode/auth.json"
      ]
    },
    "bash": {
      "deny": ["curl", "wget"]
    }
  }
}
```

OpenCode itself can use the auth token to call LLMs. Agents, subagents, skills, and tools are blocked from reading or modifying the token file. This is the critical isolation — the container prevents host-level exfiltration; the permission rules prevent agent-level exfiltration.

**Layer 6 — Network:** Full internet via rootless slirp4netns/pasta NAT. Container can't access host network directly. Only explicitly forwarded ports reachable from host.

### Error Handling Strategy

Every external command call (`podman`, `apk`, etc.) is wrapped with exit-code checking and produces a human-readable error. Errors are classified:

| Error class | Source | User sees | Fix instruction |
|------------|--------|-----------|-----------------|
| `PODMAN_NOT_FOUND` | `which podman` fails | "Podman is not installed." | Prints OS-specific install command |
| `SUBUID_NOT_CONFIGURED` | `podman run` fails with subuid error | "Rootless Podman requires subuid/subgid configuration." | Prints `/etc/subuid` setup instructions |
| `IMAGE_PULL_FAILED` | `podman pull` fails | "Failed to pull Wolfi base image from cgr.dev." | Check internet connection; suggests offline fallback |
| `APK_NETWORK_ERROR` | `apk add` fails with network error | "Package install failed — could not reach Wolfi package repos." | Run `opencode-pod doctor` to verify container networking |
| `APK_PACKAGE_NOT_FOUND` | `apk add` fails with 404 | "Package 'X' not found in Wolfi repos." | Check package name spelling in opencode-pod.toml |
| `PORT_CONFLICT` | `podman create` fails with port bind error | "Port X is in use." | Choose a different port in `[network.forward]` |
| `VOLUME_CONFLICT` | Volume name collision | "Volume for this project already exists." | Prompt: destroy and recreate, or use existing |
| `SELINUX_DENIAL` | Mount fails with SELinux AVC denial | "SELinux blocked container from accessing the project directory." | Print: `restorecon -Rv <project>` or re-run with `:Z` |
| `DISK_SPACE_LOW` | Volume create fails with ENOSPC | "Not enough disk space. Need at least 2GB free." | Suggests cleaning old containers with `opencode-pod doctor` |
| `TOML_PARSE_ERROR` | TOML parser fails | "Could not parse opencode-pod.toml:" + line number + reason | Shows the problematic line and expected format |

### Cross-Distro Detection

Reads `/etc/os-release`, maps `$ID` to install profile:

| OS | Install Podman | Subuid/subgid |
|----|---------------|---------------|
| Arch | `pacman -S podman slirp4netns fuse-overlayfs` | Manual (`/etc/subuid`) |
| Fedora | `dnf install podman` | Automatic |
| Ubuntu/Debian | `apt install podman` | Automatic (10+) |
| macOS | `brew install podman && podman machine init && podman machine start` | N/A (VM) |

`install.sh` never runs `sudo`. It prints the command and waits for user confirmation.

### User Journey

**One-time setup:**
```sh
curl -fsSL https://raw.githubusercontent.com/.../main/install.sh | bash
# Detects distro, guides through rootless podman setup
# Copies opencode-pod to ~/.local/bin and lib/ to ~/.local/share/opencode-pod/
# Pulls wolfi-base image
```

**New project:**
```sh
cd ~/projects/my-api
opencode-pod init             # create opencode-pod.toml (or skip — auto-detects)
opencode-pod setup            # one-time provisioning (~60s)
opencode-pod start            # instant — enter shell, drops into /workspace
```

**Daily use:**
```sh
cd ~/projects/my-api
opencode-pod start   # instant — reattaches to running container
opencode             # launch your AI coding agent inside
exit                 # shell exits, container keeps running
opencode-pod stop    # pause container (e.g., end of day)
```

**Debugging:**
```sh
opencode-pod logs          # see what happened in the container
opencode-pod doctor        # diagnose any setup issues
opencode-pod upgrade       # check for stale base image, add new packages
```

## Implementation Notes

- All host-side scripts use bash 4+ (`#!/usr/bin/env bash`) for portability
- Container command is `sleep infinity` — keeps container alive between exec sessions
- Container shell is zsh (`/usr/bin/zsh`)
- Shell entry via `podman exec -it --workdir /workspace` — drops directly into project directory
- No Dockerfile generation — `podman create` from base image + first-launch bootstrap
- Wolfi base image is pulled once and cached locally; `podman create` uses the cached copy
- Package changes handled by `opencode-pod upgrade` (delta detection via `apk list --installed` with version stripping)
- TOML parser in bash: read key-value pairs with basic section handling (flat, single-level sections, dotted keys); malformed TOML produces a parse error with line number
- Default packages (when none specified): `git`, `openssh`, `curl`
- `apk add` always uses `-U` (update package index before install — Wolfi base has no preloaded index)
- `apk add` exit code is not trusted — bootstrap verifies each package via `apk info -e`
- Bootstrap checkpointing: `.bootstrap-progress` file in home volume tracks completed steps (one step per line); enables cross-invocation resume on partial failure
- Config caching: parsed TOML cached as shell variables in `~/.cache/opencode-pod/`, invalidated on mtime change
- LIB_DIR falls back to `~/.local/share/opencode-pod/lib/` when script runs from installed location (not repo)
- OpenCode installed inside container via `npm install -g @anthropic-ai/opencode` during bootstrap (requires `nodejs`, `npm` in packages)

## Testing Strategy

- **bats** (Bash Automated Testing System) for unit tests (73 tests across 6 files):
  - `bats/toml.bats` — TOML parser: valid configs, malformed TOML, missing sections, comment handling, edge cases, config caching
  - `bats/distro.bats` — distro detection: known OS IDs, unknown IDs, missing `/etc/os-release`, quoted IDs, multi-line files
  - `bats/podman.bats` — container lifecycle: resolve_project, container naming, container create flag assembly, error classification (all patterns + fallback), bootstrap checkpointing, setup idempotency
  - `bats/security.bats` — hardening flags, opencode config path
  - `bats/install.bats` — installer file placement
- **Integration tests** (`bats/integration.bats`) with real Podman, skipped automatically in CI or any environment without a usable `podman`:
  - Dev user owns `/home/dev` after bootstrap (direct regression test for the `--cap-drop=ALL` / `CAP_CHOWN` ownership bug)
  - Dev user can create OpenCode data directories without `EACCES`
  - `fix_home_ownership` is idempotent (safe to run repeatedly)
- **CI:** GitHub Actions runs `shellcheck` on all `.sh` files and `bats` unit tests.
- **Release checklist:** manual test on Arch, Fedora, and Ubuntu 24.04 before tagging a release.

## Open Source Distribution

- **License:** MIT
- **Install:** `curl | sh` one-liner from raw GitHub URL
- **README:** one-liner install, quick start, config reference, security summary, Podman-vs-Docker comparison
- **CONTRIBUTING.md:** accept PRs for distro support and config improvements
- **CI:** shellcheck + bats on push/PR (GitHub Actions)

## Non-Goals (Explicitly Out of Scope)

- Docker support (this is Podman-only)
- Multi-container pods or docker-compose workflows
- IDE integration (VS Code devcontainer, IntelliJ)
- GUI or TUI management interface
- Pre-built container images (builds on-demand from Wolfi base)
- Windows host support (WSL only)
- Shell tab completion and `ocp` alias (deferred to Phase 2)

## Deferred to TODOS.md

- Shell integration (tab completion + `ocp` alias) — add when base commands are stable
- Multi-project dashboard — implement when 3+ active containers is common
- macOS support (podman machine) — Phase 2+
- Network proxy sidecar with mitmproxy TLS inspection — Phase 5
- IDE integration (VS Code devcontainer, IntelliJ) — re-evaluate in 6 months

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 1 | CLEAN (2026-07-01) | SELECTIVE EXPANSION. 6 proposals, 5 accepted, 1 deferred. 0 unresolved. |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAN (2026-07-01) | 10 issues, 10 resolved. |
| Implementation | — | — | — | DONE (2026-07-02) | 73 bats tests (unit) + 3 integration tests, 7 commits. All design decisions shipped. |

- **STATUS:** IMPLEMENTED — 73 unit tests + 3 integration tests passing. Real Podman integration tests active.
- **VERDICT:** CEO + ENG CLEARED — implementation complete
