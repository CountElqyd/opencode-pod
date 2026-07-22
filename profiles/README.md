# OpenCode Profiles

A `profiles/<name>/` directory defines a reusable OpenCode environment: skills,
agents, config, and tooling all packaged for one-command setup inside an
opencode-pod container.

## Convention

Each profile directory contains:

| File | Required | Purpose |
|------|----------|---------|
| `setup.sh` | Yes | Installs the profile inside the container (called by `opencode-pod profile install`) |
| `build.sh` | Yes | Rebuilds `<name>.tar.gz` from `src/` |
| `<name>.tar.gz` | Yes | Packaged profile source: VERSION + `src/` contents (built by `build.sh`) |
| `profile.json` | No | Local metadata — `profiles/index.json` is the canonical registry |
| `src/` | Yes | Editable source files that `build.sh` packs into the tarball |

`VERSION` is **not** a standalone file. Each profile's version is declared in
`profiles/index.json`. `build.sh` reads it from there and injects a `VERSION`
file into the tarball at build time. `setup.sh` reads it from the tarball via
`tar xzOf` for idempotency checks.

## How profiles work

1. On the host: `opencode-pod profile install <name>` fetches the profile index
   from GitHub to find the latest version, network mode, and metadata.
2. It downloads `<name>.tar.gz` and `setup.sh` from GitHub raw URLs into a temp
   directory **inside** the container (`/tmp/.opencode-profile-<name>/`).
3. It runs `bash setup.sh` as the `dev` user inside the container.
4. `setup.sh` extracts the tarball, copies config/skills/agents to
   `$HOME/.config/opencode/`, installs dependencies (npm, pip, etc.), and records
   the installed version for idempotency.
5. The temp directory is cleaned up automatically on exit.
6. Re-running is safe — the idempotency guard compares the installed version
   against the tarball's VERSION and skips if they match.

The project directory (where `opencode-pod` is run) is mounted at `/workspace`
inside the container. Profiles are **not** volume-mounted — they are fetched
from GitHub as needed.

## Adding a new profile

```bash
cp -r profiles/ralph profiles/my-profile
# Edit src/ files, modify setup.sh
# Register in profiles/index.json with a version
cd profiles/my-profile && bash build.sh
```

Then install via: `opencode-pod profile install my-profile`

## Profile types

**Tarball profiles** (e.g. `ralph/`): the primary payload ships inside
`<name>.tar.gz` — skills, agents, commands, config, framework code. `setup.sh`
extracts and installs everything from the tarball.

**Package-manager profiles** (e.g. `swarm/`): the primary installation comes
from an external package manager (npm, pip). They still have a `build.sh` and
tarball — the tarball carries supplementary config files (`src/config/`) that
`setup.sh` copies after running the package manager. The distinction is where
the main payload originates, not whether a tarball exists.

## Built-in profile: `ralph`

The `ralph/` profile bundles the full GSD-Core + G-Stack ecosystem plus an optional
[ralph-loop-v2](ralph/src/skills/ralph-loop-v2/) orchestration skill for autonomous
build-loop execution (plan → gate → execute → verify → ship). It also includes a
pre-built [fabric-mcp](ralph/src/fabric-mcp/) MCP server for Fabric AI pattern
integration.

See `profiles/ralph/src/config/opencode.json` for the reference permission model.

## Versioning

Each profile's version is declared in `profiles/index.json`. `build.sh` reads
it and bakes a `VERSION` file into the tarball. `setup.sh` checks this before
installing — if the version matches what's recorded in `$HOME/.<name>-version`,
installation is skipped (idempotency guard).
