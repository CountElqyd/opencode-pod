# PROFILE-ralph — Ralph Profile Guide

## What this is / when to use it

The **ralph** profile turns the opencode-pod container into a full
Goal-Driven Development (GSD) + G-Stack environment: the GSD-Core workflow
engine, the G-Stack review pipeline (CEO/Eng/Design/DX review skills), the
ralph-loop-v2 orchestration skill for autonomous build loops, and a large
catalogue of `/gsd-*` commands and agents (see `opencode-pod profile info ralph`
for the exact counts). It also bundles a pre-built **fabric-mcp** MCP server
plus the `fabric-ai` CLI for AI-pattern analysis. Use it for end-to-end
autonomous development sessions: plan → gate → execute → verify → ship.

## Quick start

1. Start the container: `opencode-pod start` then `opencode-pod shell`.
2. Run opencode inside the container.
3. In the session, run `/gsd-help` to see the command surface.
4. Kick off a project: `/gsd-new-project` (full setup) or `/gsd-quick` (lightweight).

## Key commands

| Command | What it does |
|---|---|
| `/gsd-help` | Show GSD command reference (add `--brief`, `--full`, or a topic) |
| `/gsd-new-project` | Initialize a new GSD project (milestones, phases, planning) |
| `/gsd-quick` | Lightweight GSD workflow for small, fast tasks |
| `/gsd-fast` | Fast-tracked workflow when speed beats ceremony |
| `/gsd-phase` | Work with phases (add/remove/list/insert) |
| `/gsd-execute-phase` | Execute a plan's phase, optionally per-wave (`--wave N`) or inline (`--interactive`) |
| `/gsd-code-review` | Run the GSD code-reviewer agent against recent work |
| `/gsd-review` | Gated review entry point in the G-Stack pipeline |
| `/gsd-debug` | Hypothesis-driven debugging workflow |
| `/gsd-verify-work` | Verify work before completion |
| `/gsd-ship` | Ship a completed milestone |
| `/gsd-graphify` | Build/query a codebase graph (`/gsd-graphify build`, `/gsd-graphify query`) |

## Agents

| Agent | Use when… |
|---|---|
| `gsd-planner` | Turning a phase description into a detailed execution plan |
| `gsd-executor` | Executing plan phases end-to-end |
| `gsd-verifier` | Checking implementation satisfies the plan (levels 1-3) |
| `gsd-code-reviewer` | Security/correctness review of a code change |
| `gsd-debugger` | Systematic, hypothesis-driven debugging |
| `gsd-codebase-mapper` | Building a codebase map in `.planning/codebase/` |
| `gsd-security-auditor` | Security audit of the implementation |
| `gstack-gate` | G-Stack quality gate before merge |

More agents are available — use `/gsd-help` to discover the rest.

## Config layout

- `~/.config/opencode/opencode.json` — hardened permission model (bash/edit/read
  denylists), fabric MCP wiring, superpowers plugin, `doom_loop: allow`.
- `~/.config/opencode/gsd-core/` — the GSD-Core 1.5.0 workflow engine.
- `~/.local/share/fabric-mcp/` — the fabric MCP server (node) with its dependencies.
- `~/.local/bin/fabric-ai` — the fabric-ai CLI (also served as the `fabric` MCP env path).
- `~/.config/opencode/skills/`, `agents/`, `command/` — profile skills, agents, and `/gsd-*` commands.

## Requirements & network

- Requires: `nodejs`, `npm`, `python3`, `uv` (installed by the profile).
- Network mode: `host` — needed to reach a local LLM (ollama/llama.cpp) on the host.
- During install/update, the profile may prompt to apply `opencode-pod.toml`
  changes (e.g. `[network] mode = "host"`). Accepting destroys and recreates the
  container; declining cancels install (or warns on update).

## Recommended workflow

`/gsd-new-project` → let GSD scaffold milestones/phases → `/gsd-execute-phase`
per phase → `/gsd-code-review` after each milestone → `/gsd-verify-work` →
`/gsd-ship`. For fully autonomous build loops, use the `ralph-loop-v2` skill or
the G-Stack review pipeline (`/gsd-review`) before merge.

## Maintenance

- Update: `opencode-pod profile update ralph` (or `--force` to re-install same version).
- Installed version is recorded in `~/.ralph-version`.
- The guide refreshes on profile version change; edits you make survive a
  same-version reinstall. Delete it and any install restores it.

## Troubleshooting

- **fabric-mcp warning**: "fabric-mcp npm install failed" appears during setup —
  the MCP server was not wired. Re-run `opencode-pod profile update ralph --force`.
- **Tarball checksum mismatch**: network glitch — retry the install/update.
- **`opencode-ai@<version>` 404**: the pinned npm tag is missing — update
  opencode-pod first, then retry.
- **Local LLM unreachable**: confirm the profile applied `network: host`
  (see Requirements above); manually editing TOML requires `opencode-pod destroy && opencode-pod setup`.

## Footer

- Check the installed version: `opencode-pod profile info ralph`
- Upstream: GSD-Core (opengsd/gsd-core), fabric (danielmiessler/fabric), superpowers (obra/superpowers)
