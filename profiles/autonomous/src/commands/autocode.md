---
description: Launch a fire-and-forget autonomous GSD run in-session from a gstack-reviewed design doc.
argument-hint: "[design-doc] [--from N] [--to N] [--only N] [--watch] [--timeout 4h] [--prepare-only] [--skip-prepare]"
effort: max
requires: [phase, progress]
agent: autocode-runner
tools:
  read: true
  write: true
  bash: true
  glob: true
  grep: true
  agent: true
---
<objective>
Run a fire-and-forget autonomous GSD run in the current opencode session. The input is a gstack-reviewed design doc (already approved — do NOT run gstack review). Execute GSD's `/gsd-autonomous` against it, resolving every decision point through `autocode-decider` instead of asking the user. NEVER call the `question` tool. Stop only when the milestone lifecycle completes, the timeout fires, or a hard blocker cannot be resolved by policy.
</objective>

<context>
Flags:
- `anchor` (required) — the starting design artifact. Resolution priority: (1) `@`-attached reference (content in prompt), (2) positional `anchor-path`, (3) the newest `docs/planning/*-design-doc.md` by mtime (the gstack convention of reading the latest `*-design-doc.md`). The anchor may be ANY package member — design doc, gstack review, brainstorming spec, or writing-plans task. Its topic slug is the basename minus the convention tokens: the `YYYY-MM-DD-` date prefix and the `-design-doc` / `-design` / `-<review-type>-review` suffixes.
- `--from N` / `--to N` / `--only N` — forwarded to `/gsd-autonomous` (resume/scope controls).
- `--watch` — poll `git log --oneline -5` and `.planning/STATE.md` between steps; report phase transitions; abort if neither the latest commit nor the STATE.md content/mtime changes for 15 consecutive minutes.
- `--timeout 4h` — hard stop after the given duration (default 4h).
- `--prepare-only` — run the prepare pass only, then exit.
- `--skip-prepare` — assume CONTEXT.md/RESEARCH.md already seeded; skip the prepare pass.

Design package: from the topic slug, discover every sibling artifact:
- `docs/planning/<topic>-*.md` — gstack artifacts (design doc, ceo/eng/design reviews).
- `docs/specs/*-<topic>-design.md` — superpowers brainstorming specs.
- `docs/plans/*-<topic>.md` — superpowers writing-plans task plans.
Date collisions (same topic, multiple dates) resolve to the newest mtime; list discovered package paths in the run-start report. If the anchor resolved from content only (`@`-attach), skip discovery and warn. If the package is only the anchor, proceed with the single doc and note it.

Composite spec: the package's design doc (`docs/planning/<topic>-design-doc.md`; fallback: the anchor itself when the package has no design doc) is the PRIMARY spec — it drives phase generation. Every other member is appended with a provenance header (`# From <path>`): gstack review verdicts are authoritative constraints per domain (CEO scope/priority, Eng architecture/data flow, Design UX), and the plan file's tasks are required deliverables the execution must satisfy.

Pipeline:
1. **Preflight (fail fast).**
   - Resolve the anchor per the priority above. If no anchor resolves, abort with: "No design doc found. Attach one with @, pass a path (e.g. /autocode docs/planning/<topic>-design-doc.md), or run office-hours/brainstorming first." The anchor must be in a locked/approved state.
   - Discover the design package per the rules above; report the package before starting.
   - If the package resolved from paths, `graphify-out/graph.json` must be newer than the NEWEST package member's mtime; if stale, abort and tell the user to re-run `graphify build`. If only `@`-attached content with no usable path, warn (do not abort) when graph.json is absent or stale.
   - Git identity must resolve (`git config user.name` and `git config user.email`); abort with instructions if either is missing — GSD commits every phase and the container sets no global identity.
2. **Prepare pass (hands-free).** For each incomplete phase in the run range (respecting `--from/--to/--only`), resolve phase state via `gsd_run query init.milestone-op` / `init.phase-op`. The entire design package is ground truth for this pass:
   - If `has_context` is false (no CONTEXT.md) → run the smart-discuss step with the package content and have `autocode-decider` auto-accept the recommended answers, producing CONTEXT.md that encodes review verdicts and plan deliverables.
   - If `has_research` is false (no RESEARCH.md) → run the phase researcher (`gsd-plan-phase --research-phase <N>`), feeding package constraints, producing RESEARCH.md.
   - Retry once on failure. After two failures for an in-range phase, abort with a resume path via `--skip-prepare`. Out-of-range phases warn and continue.
3. **Run pass.** Run `/gsd-autonomous` with the composite spec (attached content or resolved package) as the spec, forwarding `--from/--to/--only`. At every GSD decision point, dispatch `autocode-decider` with the phase, decision type, options, and recommendations; apply its verdict and continue. The run ends when the milestone lifecycle completes — it does **not** create a PR or push branches.
4. **Watch/stop.** With `--watch`, poll progress between steps; abort on a 15-minute stall. With `--timeout`, hard-stop at the duration and emit a completion report (what shipped, what remains, resume via `--from N`).
</context>

<process>
Execute end-to-end per the pipeline. Preserve all GSD workflow gates. NEVER call the `question` tool. Dispatch every decision point to `autocode-decider`.
</process>

<execution_context>
This session runs inside the container with the `autonomous` profile installed. GSD is configured with `tdd_mode: true`, `use_worktrees: false`, and injected superpowers skills; quality gates are off by default. The `autocode-runner` primary agent and `autocode-decider` subagent are installed in this profile.
</execution_context>
