# Plan: Ralph Profile for opencode-pod

## Goal
Add a versioned profile to the `opencode-pod` repo containing skills, agents, config, and fabric-mcp — so users can deploy a ready-to-use OpenCode setup inside any opencode-pod container.

## Design decisions
- **Profile is decoupled from the tool.** `opencode-pod` CLI is unchanged. No new subcommands, no new flags.
- **Tarball, not source dirs.** Skills/agents/config/fabric-mcp are packaged as `ralph.tar.gz` to keep the repo footprint small.
- **Two install paths.** Local (repo cloned, tarball on disk) via `setup.sh` directly. Remote (curl | sh) via `install-profile.sh` which downloads from GitHub and delegates to `setup.sh`.
- **`install.sh` stays lean.** The base CLI installer does NOT bundle profiles — they are fetched on demand by `install-profile.sh`.
- **Host networking for local LLM.** `network = "host"` in opencode-pod.toml is the right default for reaching llama.cpp on `127.0.0.1:8080`.

## Repo additions / changes

| File | Purpose |
|------|---------|
| `install-profile.sh` | Standalone script for remote profile install (runs inside the container) |
| `profiles/ralph/` | Profile directory |
| `profiles/ralph/setup.sh` | Extracts tarball, files config/skills/agents, installs MCP deps |
| `profiles/ralph/ralph.tar.gz` | Packaged profile (skills, agents, config/opencode.json, fabric-mcp source) |
| `profiles/ralph/build.sh` | Rebuilds tarball from source files |
| `profiles/README.md` | Documents profile convention and lists built-in profiles |

## User flows

### Flow A: Repo cloned (local)
```bash
git clone <repo> my-project
cd my-project
opencode-pod start

# Inside container — repo is bind-mounted at /workspace/opencode-pod/
bash /workspace/opencode-pod/profiles/ralph/setup.sh
opencode
```

### Flow B: Curl-installed CLI (remote)
```bash
# Host side
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install.sh | sh
cd my-project
opencode-pod start

# Inside container — download and install profile
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install-profile.sh | sh -s ralph
opencode
```

### Flow C: Existing profile re-install (idempotent)
```bash
# Either path — setup.sh checks VERSION, skips if already installed
bash /workspace/opencode-pod/profiles/ralph/setup.sh
# or
curl -fsSL https://raw.githubusercontent.com/CountElqyd/opencode-pod/main/install-profile.sh | sh -s ralph
```

## install-profile.sh behavior
1. Validates profile name is provided and exists in repo
2. Downloads `<name>.tar.gz` and `setup.sh` from GitHub to a temp dir
3. Runs `setup.sh` — it finds the tarball via `$SCRIPT_DIR`
4. Cleans up temp dir
5. Accepts `OPCODE_POD_REPO` and `OPCODE_POD_VERSION` env vars for forks/pinning

## setup.sh responsibilities
1. Validate environment (tarball exists, HOME exists)
2. Idempotency guard — compare VERSION from tarball against `~/.ralph-version`
3. Extract tarball to temp dir
4. Copy `config/opencode.json` → `~/.config/opencode/`
5. Copy `skills/*` → `~/.config/opencode/skills/`
6. Copy `agents/*` → `~/.config/opencode/agents/`
7. Copy `commands/*` → `~/.config/opencode/command/`
8. Install GSD-Core: `~/.config/opencode/gsd-core/`
9. Install fabric-mcp: npm install in `~/.local/share/fabric-mcp/`
10. Install fabric-ai CLI: `pip3 install --user fabric-ai` (or uv fallback)
11. Record version to `~/.ralph-version`

## What's NOT changing
- `opencode-pod` CLI — no new flags, no modified bootstrap, no new mounts
- `lib/podman.sh` — no volume changes for profiles
- `install.sh` — no profile bloat, stays focused on CLI tool only
- Auth flow — remains manual (SSH agent, git creds, opencode auth)
- Profiles remain a manual install step inside the container
