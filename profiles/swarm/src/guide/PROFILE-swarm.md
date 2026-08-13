# PROFILE-swarm — Swarm Profile Guide

## What this is / when to use it

The **swarm** profile installs the **opencode-swarm** plugin
(`npm install -g opencode-swarm` + `opencode-swarm install`) for
verification-gated, architect-led multi-agent development: an architect that
plans, parallel coders, a gated QA pipeline, and built-in SAST (exact agent and
command counts via `opencode-pod profile info swarm`). The architect agent plans,
multiple coders implement in parallel, and a reviewer/test pipeline gates
merges. Use it when you want structured multi-agent development with an
enforced quality gate instead of a single-agent session.

## Quick start

1. Start the container: `opencode-pod start` then `opencode-pod shell`.
2. Run opencode inside the container.
3. The plugin registers its commands on install — check the opencode command
   palette (or the plugin's own `--help`) for the swarm command set.
4. Point the architect at a task and let the gated pipeline plan, code, and review.

## Key commands

The command set is registered by the `opencode-swarm` plugin at install time.
The core surface follows an architect-led flow: kick off a session, the
architect plans, coders implement, and the gated QA pipeline reviews before
completion. Run `opencode-swarm --help` (in the container) or the plugin's
installed commands to see the exact names for your version.

## Agents

| Agent | Use when… |
|---|---|
| `architect` | Planning the approach and decomposing the work |
| `coder` | Implementing planned tasks (parallelizable) |
| `reviewer` | Reviewing implementation against the plan |
| `test_engineer` | Writing/running the verification and QA gate |
| `explorer` | Researching the codebase before planning |

Model overrides are configured in `opencode-swarm.json`.

## Config layout

- `~/.config/opencode/opencode-swarm.json` — session and project tuning knobs:

| Knob | Meaning |
|---|---|
| `session_mode` / `project_mode` | `balanced` (default) — session vs. project pacing |
| `max_parallel_coders` | `1` — max coders working in parallel |
| `council` | `false` — group review before decisions |
| `ui_review` | `false` — UI/UX review gate |
| `mutation_testing` | `false` — mutation testing gate |

- `~/.config/opencode/opencode.json` — base opencode config.
- Agent model overrides: `architect`, `coder`, `reviewer`, `test_engineer`,
  `explorer` → `opencode/deepseek-v4-flash-free`.

## Requirements & network

- Requires: `nodejs`, `npm`.
- Network mode: `bridge` — no host networking needed to reach external LLM APIs.
- During install/update, the profile may prompt to apply `opencode-pod.toml`
  changes; accepting destroys and recreates the container.

## Recommended workflow

Open a session, invoke the swarm flow, give the architect a goal, and let the
pipeline decompose → code → QA-gate → review. Adjust `max_parallel_coders` for
throughput vs. token cost, and enable `council`/`ui_review`/`mutation_testing`
for stricter gates.

## Maintenance

- Update: `opencode-pod profile update swarm` (or `--force` to re-install same version).
- Installed version is recorded in `~/.swarm-version`.
- The guide refreshes on profile version change; edits you make survive a
  same-version reinstall. Delete it and any install restores it.

## Troubleshooting

- **`npm not found`** during install — the container lacks npm; re-run
  `opencode-pod profile update swarm --force` after confirming the `requires`
  packages (`nodejs`, `npm`) are present.
- **Plugin commands missing in session** — the plugin was installed but not
  initialized; re-run `opencode-swarm install` inside the container.
- **Tarball checksum mismatch** — network glitch; retry the install/update.

## Footer

- Check the installed version: `opencode-pod profile info swarm`
- Upstream: opencode-swarm (npm) — see the plugin's docs for the full command reference.
