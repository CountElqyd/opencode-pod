---
description: Launch a fire-and-forget autonomous GSD run in-session from a gstack-reviewed design doc.
argument-hint: "[design-doc] [--from N] [--to N] [--only N] [--watch] [--timeout 4h] [--prepare-only] [--skip-prepare]"
effort: max
requires: [phase, progress]
tools:
  read: true
  write: true
  bash: true
  glob: true
  grep: true
---
<objective>
Run a fire-and-forget autonomous GSD run in the current opencode session. The input is a gstack-reviewed design doc (already approved — do NOT run gstack review). Execute GSD's `/gsd-autonomous` against it, resolving every decision point through `autocode-decider` instead of asking the user. NEVER call the `question` tool. Stop only when the milestone lifecycle completes, the timeout fires, or a hard blocker cannot be resolved by policy.
</objective>

<context>
Flags:
- `design-doc` (required) — the gstack-reviewed spec. Resolution priority: (1) `@`-attached reference (content in prompt), (2) positional `design-doc-path`, (3) default `docs/planning/design-doc.md`.
- `--from N` / `--to N` / `--only N` — forwarded to `/gsd-autonomous` (resume/scope controls).
- `--watch` — poll `git log --oneline -5` and `.planning/STATE.md` between steps; report phase transitions; abort if neither the latest commit nor the STATE.md content/mtime changes for 15 consecutive minutes.
- `--timeout 4h` — hard stop after the given duration (default 4h).
- `--prepare-only` — run the prepare pass only, then exit.
- `--skip-prepare` — assume CONTEXT.md/RESEARCH.md already seeded; skip the prepare pass.

Pipeline:
1. **Preflight (fail fast).**
   - Resolve the design doc per the priority above. If none resolves, abort with: "No design doc found. Attach it with @ or pass a path (e.g. /autocode docs/planning/design-doc.md)." The resolved doc must be in a locked/approved state.
   - If a resolvable path exists, `graphify-out/graph.json` must be newer than the design doc's mtime; if stale, abort and tell the user to re-run `graphify build`. If only `@`-attached content with no usable path, warn (do not abort) when graph.json is absent or stale.
   - Git identity must resolve (`git config user.name` and `git config user.email`); abort with instructions if either is missing — GSD commits every phase and the container sets no global identity.
2. **Prepare pass (hands-free).** For each incomplete phase in the run range (respecting `--from/--to/--only`), resolve phase state via `gsd_run query init.milestone-op` / `init.phase-op`:
   - If `has_context` is false (no CONTEXT.md) → run the smart-discuss step and have `autocode-decider` auto-accept the recommended answers, producing CONTEXT.md.
   - If `has_research` is false (no RESEARCH.md) → run the phase researcher (`gsd-plan-phase --research-phase <N>`), producing RESEARCH.md.
   - Retry once on failure. After two failures for an in-range phase, abort with a resume path via `--skip-prepare`. Out-of-range phases warn and continue.
3. **Run pass.** Run `/gsd-autonomous` with the design doc (attached content or resolved path) as the spec, forwarding `--from/--to/--only`. At every GSD decision point, dispatch `autocode-decider` with the phase, decision type, options, and recommendations; apply its verdict and continue. The run ends when the milestone lifecycle completes — it does **not** create a PR or push branches.
4. **Watch/stop.** With `--watch`, poll progress between steps; abort on a 15-minute stall. With `--timeout`, hard-stop at the duration and emit a completion report (what shipped, what remains, resume via `--from N`).
</context>

<process>
Execute end-to-end per the pipeline. Preserve all GSD workflow gates. NEVER call the `question` tool. Dispatch every decision point to `autocode-decider`.
</process>

<execution_context>
This session runs inside the container with the `autonomous` profile installed. GSD is configured with `tdd_mode: true`, `use_worktrees: false`, and injected superpowers skills; quality gates are off by default. The `autocode-runner` primary agent and `autocode-decider` subagent are installed in this profile.
</execution_context>