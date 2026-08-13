# PROFILE-autonomous — Autonomous Profile Guide

## What this is / when to use it

The **autonomous** profile is a lean execution profile for zero-interruption
autonomous sessions: GSD-Core 1.5.0 (with `tdd_mode`) drives execution, the
Graphify CLI builds a zero-token codebase graph, and curated superpowers
skills (`systematic-debugging`, `verification-before-completion`,
`requesting-code-review`, `self-consistency-reasoner`, `context-management`)
keep runs rigorous. No fabric-mcp. Use it to launch fire-and-forget runs from an
approved design doc, or to work with graph-first codebase answering.

## Quick start

1. Start the container: `opencode-pod start` then `opencode-pod shell`.
2. Run opencode inside the container.
3. New project: `/new-project`. Existing project: `/setup-project` (idempotent).
4. Launch a run: `/autocode docs/planning/design-doc.md`.

## Key commands

| Command | What it does |
|---|---|
| `/new-project` | Bootstrap a NEW project: graphify graph + freshness hook + AGENTS.md "Graphify First" contract + superpowers memory |
| `/setup-project` | Configure an EXISTING project idempotently (incremental graph update, append-only contract) |
| `/autocode <doc>` | Fire-and-forget autonomous GSD run from an approved design doc (see flags below) |
| `/graphify query "<q>"` | Answer codebase questions from the graph (`--budget 1500`) |

`/autocode` flags: `--from N --to N --only N` (resume/scope), `--watch` (stall
detection), `--timeout 4h`, `--prepare-only`, `--skip-prepare`.

## Agents

| Agent | Use when… |
|---|---|
| `autocode-runner` | Primary agent for fire-and-forget autonomous GSD runs (150 steps, `question: deny`) |
| `autocode-decider` | Read-only policy engine resolving GSD decision points without asking the user |
| `code-reviewer` | Reviewing completed implementation |
| `red-team` | Adversarial review / security red-teaming |

## Config layout

- `~/.config/opencode/opencode.json` — hardened permission model + providers:
  `deepseek-v4-flash-free` (default) and `ollama` (local, `http://localhost:11434/v1`).
- `/workspace/.planning/config.json` — GSD project config seeded at install
  (non-clobbering — existing file is kept) with the profile's GSD tuning:
  `tdd_mode: true`, `use_worktrees: false`, `quality_gates: off`, and the
  injected superpowers skills on `gsd-executor` via `agent_skills`.
- `~/.config/opencode/skills/superpowers/` — the curated superpowers skills.
- `~/.config/opencode/command/` — `/autocode`, `/new-project`, `/setup-project`.
- `~/.local/bin/graphify` — the Graphify CLI (installed via `uv`).

## Requirements & network

- Requires: `nodejs`, `npm`, `uv`.
- Network mode: `host` — REQUIRED to reach a local LLM (ollama/llama.cpp) on the host.
- During install/update, the profile prompts to apply `[network] mode = "host"`;
  accepting destroys and recreates the container. Declining cancels install (or warns on update).

## Recommended workflow

`/setup-project` (or `/new-project`) to seed the graph and memory →
`/autocode <design-doc>` for a fire-and-forget run → `/graphify query "<q>"`
for all subsequent codebase questions → `code-reviewer`/`red-team` on the result.

## Maintenance

- Update: `opencode-pod profile update autonomous` (or `--force` to re-install same version).
- Installed version is recorded in `~/.autonomous-version`.
- The guide refreshes on profile version change; edits you make survive a
  same-version reinstall. Delete it and any install restores it.

## Troubleshooting

- **`/autocode` aborts: graph is stale** — re-run `graphify build` (or the graph
  must be newer than the design doc). For `@`-attached docs a stale graph only warns.
- **`/autocode` aborts: git identity missing** — set `git config user.name` / `user.email`
  (GSD commits every phase).
- **Local LLM unreachable** — confirm `network: host` was applied; without it the
  container cannot reach ollama on the host.
- **Graph builds with no doc embedding** — no `GEMINI_API_KEY`; the pipeline
  re-runs `--code-only` and continues.

## Footer

- Check the installed version: `opencode-pod profile info autonomous`
- Upstream: GSD-Core (opengsd/gsd-core), Graphify (graphify CLI + skill), superpowers (obra/superpowers)
