# OpenCode Profiles

A `profiles/<name>/` directory defines a reusable OpenCode environment: skills, agents, config, and tooling all packaged for one-command setup inside an opencode-pod container.

## Convention

Each profile directory contains:

| File | Required | Purpose |
|------|----------|---------|
| `setup.sh` | Yes | Installs the profile inside the container |
| `build.sh` | Yes | Rebuilds `<name>.tar.gz` from `src/` |
| `<name>.tar.gz` | Yes | Packaged profile source (built by `build.sh`) |
| `VERSION` | Yes | Semver version checked by `setup.sh` |
| `src/` | Yes | Editable source files for the profile |

## How profiles work

1. The repo root is volume-mounted into the container at `/opencode-pod/`
2. Inside the container, run: `bash /opencode-pod/profiles/<name>/setup.sh`
3. `setup.sh` extracts the tarball, copies config/skills/agents, and installs dependencies
4. Re-running `setup.sh` is safe — idempotency guard skips completed installs

## Adding a new profile

```bash
cp -r profiles/ralph profiles/my-profile
# Edit src/ files, modify setup.sh, update VERSION
cd profiles/my-profile && bash build.sh
```

## Built-in profile: `ralph`

The `ralph/` profile bundles the full GSD-Core + G-Stack ecosystem plus an optional
[ralph-loop-v2](ralph/src/skills/ralph-loop-v2/) orchestration skill for autonomous build-loop
execution (plan → gate → execute → verify → ship). It also includes a pre-built
[fabric-mcp](ralph/src/fabric-mcp/) MCP server for Fabric AI pattern integration.

See `profiles/ralph/src/config/opencode.json` for the reference permission model.

## Versioning

Each profile has its own `VERSION` file. `setup.sh` checks the version before applying — if the installed version matches, it skips re-installation (idempotency guard).
