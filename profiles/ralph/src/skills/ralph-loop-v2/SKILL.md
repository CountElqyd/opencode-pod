---
name: ralph-loop-v2
description: |
  Integrated autonomous build-loop orchestrator combining G-Stack (role-based review),
  GSD-Core (context engineering + multi-agent orchestration), and Superpowers (TDD
  discipline) into a single pipeline. Pure metadata router — never reads plan content,
  source code, or research output into orchestrator context. Resumable state.
  Use when asked to "build loop", "ralph loop", "route loop", "autonomous build",
  "build it all", or "run the full pipeline".
  Proactively suggest when the user has a spec/plan they want built autonomously.
triggers:
  - build loop
  - ralph loop
  - route loop
  - autonomous build
  - build it all
  - execute spec
  - run pipeline
  - ralph loop v2
  - build loop v2
compatibility: opencode
license: MIT
---

# Ralph Loop v2 — Integrated Build-Loop Orchestrator

## The Iron Law

**You never write production code. You never read plan content, source code, research output, or verification reports into your context.** Your job is pure coordination: read state metadata, dispatch subagents, receive metadata verdicts, update state, repeat. All heavy lifting happens in fresh subagent sessions that read `.planning/` from disk.

**What you track (metadata only):**
- Phase IDs, names, statuses
- Plan counts per phase
- File paths (paths only — never file contents)
- Wave counts and completion status
- Gate verdicts (pass/fail + concern counts)
- Subagent dispatch instructions

**What you NEVER load into your context:**
- PLAN.md file contents
- RESEARCH.md contents
- CONTEXT.md contents
- Source code
- Test output
- Verification reports

## Prerequisites

- GSD-Core installed: `npx @opengsd/gsd-core@latest --opencode --global`
- G-Stack installed: skills at `~/.config/opencode/skills/gstack-*`
- Superpowers loaded: via OpenCode plugin system
- Node.js 18+ available

## State Management

### Authoritative State

`.planning/STATE.md` is the primary state file (GSD-Core native format). It tracks:
- Current milestone and phase
- Per-phase status (planned, executing, verified, shipped)
- Per-plan completion within each phase
- Decisions, blockers, metrics

### Legacy Compatibility

`~/.gstack/projects/$SLUG/build-loop.json` is a secondary state file for:
- Crash recovery when `.planning/` is unavailable
- Backwards compatibility with gstack tooling
- Quick phase metadata without parsing STATE.md

### Reconciliation on Resume

```
1. Read .planning/STATE.md if it exists → extract current phase/progress
2. Read build-loop.json if it exists → extract previous orchestrator phase
3. If .planning/ has newer data → it wins
4. If build-loop.json has phases not in .planning/ → import them
5. Write reconciled state to both files
```

## Configuration

Read `.planning/config.json` for the `ralph_loop` section. Expected schema:

```json
{
  "ralph_loop": {
    "gstack_gate": {
      "enabled": true,
      "mode": "full",
      "skip_for": [],
      "max_concerns_auto_approve": 3
    },
    "verification": {
      "structural": true,
      "functional_qa": false,
      "design_review": false,
      "security_audit": false,
      "app_url": null
    },
    "shipping": {
      "auto_ship": false,
      "require_review": true,
      "draft_pr": false
    },
    "execution": {
      "tdd_mode": true,
      "max_retries_per_phase": 3,
      "max_decision_calls": 5,
      "max_phases": 15
    }
  }
}
```

Defaults when `ralph_loop` section is absent: gstack_gate enabled in `eng-only` mode, structural verification only, no auto-ship, TDD enabled, 3 retries, 5 decision calls.

---

## PHASE 0: INTAKE

**Goal:** Ensure a project specification exists. Load or create `.planning/` with PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md.

### Step 0.1: Check for existing project

```
IF .planning/PROJECT.md exists:
  → Read PROJECT.md, STATE.md for orientation
  → SKIP to Phase 1 (brownfield — project already initialized)
```

### Step 0.2: Detect spec file

Search for spec files in priority order:
1. User-provided path (from command args)
2. `DESIGN.md` at repo root
3. `SPEC.md` at repo root
4. `.planning/DESIGN.md`
5. `docs/specs/*.md`
6. `~/.gstack/projects/$SLUG/ceo-plans/*.md`

### Step 0.3: Initialize project

**If spec file found:**
- Run: `npx @opengsd/gsd-core gsd-tools query init.new-project --auto --spec <path>`
- OR dispatch a subagent that runs `gsd-new-project` workflow (load `gsd-new-project` skill from `~/.config/opencode/skills/gsd-new-project/SKILL.md` with `--auto @<spec_path>`)
- This creates: PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, config.json, research/

**If no spec file found:**
- Interactive mode: Tell the user a spec is required. Offer to run G-Stack spec pipeline (office-hours → plan-ceo-review → plan-eng-review). Save output as DESIGN.md. Then run gsd-new-project --auto @DESIGN.md.
- Headless/spawned mode: Report BLOCKED. "No spec file found. Provide a path to a spec file."

### Step 0.4: Initialize build-loop state

Create `~/.gstack/projects/$SLUG/build-loop.json` with:
- `project` from slug
- `spec_source` pointing to the spec file
- `phases`: empty array
- `completed_count`: 0
- `total_phases`: 0
- `created_at`: current timestamp

Report: "State initialized. .planning/ ready. Moving to Phase 1: Planning."

---

## PHASE 1: PLAN (GSD-Core Decomposition)

**Goal:** Decompose the spec into phases, each with research-backed, verified plans. Orchestrator sees only metadata.

### Step 1.1: Dispatch ralph-planner subagent

Use the Task tool with `subagent_type: "ralph-planner"`. The subagent receives:
- Path to `.planning/` directory (absolute)
- Path to the spec file (absolute)
- Instruction: run discuss→plan pipeline, return metadata JSON

```
Task dispatch:
  subagent: ralph-planner
  prompt: |
    Run the GSD-Core discuss→plan pipeline for this project.
    .planning/ directory: {absolute_path_to_planning}
    Spec file: {absolute_path_to_spec}
    Return structured metadata JSON with all phases, plans, and wave counts.
    Use --auto flags for all GSD-Core commands.
```

### Step 1.2: Process metadata

The subagent returns a JSON block:

```json
{
  "project": "my-app",
  "total_phases": 5,
  "phases": [
    {
      "id": 1,
      "name": "Auth",
      "goal": "User registration and login",
      "plans": ["01-auth-PLAN.md", "01-session-PLAN.md"],
      "plan_count": 2,
      "files": ["src/auth/", "tests/auth/"],
      "dependencies": [],
      "status": "planned"
    }
  ],
  "status": "ready"
}
```

### Step 1.3: Update state

Write phases to `build-loop.json` from metadata. Each phase entry:
```json
{
  "id": 1,
  "name": "Auth",
  "goal": "User registration and login",
  "plans": ["01-auth-PLAN.md", "01-session-PLAN.md"],
  "plan_count": 2,
  "files": ["src/auth/", "tests/auth/"],
  "dependencies": [],
  "status": "pending",
  "retries": 0,
  "started_at": null,
  "completed_at": null,
  "gates_passed": [],
  "verdicts": {}
}
```

Set `total_phases` in build-loop.json. Report phase breakdown to user.

**Context cost: ~3%** (JSON metadata only, no plan content).

---

## PHASE 1.5: G-STACK QUALITY GATE

**Goal:** Validate GSD-Core plans with G-Stack role-based review before execution. Optional, config-driven.

### Step 1.5.1: Check config

Read `ralph_loop.gstack_gate.enabled` from `.planning/config.json`.
- If `false` or absent → SKIP to Phase 2.
- If `true` → proceed with gate.

### Step 1.5.2: Dispatch gstack-gate subagent

For each pending phase (or only phases not in `skip_for` list):

```
Task dispatch:
  subagent: gstack-gate
  prompt: |
    Validate Phase {N} plans before execution.
    Phase ID: {N}
    Plan directory: {absolute_path}/.planning/phases/{N}/
    Gate mode: {mode from config}  (full | eng-only | design-only)
    Max auto-approve concerns: {max_concerns_auto_approve}
```

The subagent returns:
```json
{
  "phase_id": 1,
  "pass": true,
  "reviews_run": ["eng"],
  "concerns_high": 0,
  "concerns_all": 2,
  "recommendations": ["...", "..."],
  "auto_resolved": 2
}
```

### Step 1.5.3: Process gate verdict

- If `pass == true`: update phase `gates_passed` in build-loop.json, continue to Phase 2.
- If `pass == false` and `concerns_high > 0`: mark phase status as `gated`, log recommendations, raise to user.
- If `pass == false` but `concerns_high == 0` and `concerns_all <= max_concerns_auto_approve`: auto-approve, log concerns, continue.

**Context cost: ~2%** (per-phase JSON verdicts only).

---

## PHASE 2: EXECUTE (GSD-Core Waves + Superpowers TDD)

**Goal:** Execute all pending phases. Each phase runs wave-based parallel execution via GSD-Core.

### Step 2.1: Phase Loop

```
FOR each phase in build-loop.json where status is "pending" or "failed" (retries < max):
  
  # Mark in progress
  phase.status = "in_progress"
  phase.started_at = now()
  save build-loop.json
  
  # Dispatch gsd-executor via GSD-Core workflow
  Dispatch Task subagent with the gsd-execute-phase workflow.
  The subagent loads the gsd-execute-phase skill from 
  `~/.config/opencode/skills/gsd-execute-phase/SKILL.md` and follows it.
  
  The gsd-execute-phase workflow handles:
  - Wave analysis (dependency grouping)
  - Parallel executor dispatch (build-executor agents with Superpowers TDD)
  - Per-wave progress tracking
  - Per-plan SUMMARY.md generation
  - Atomic git commits
  
  DO NOT pass --interactive flag (autonomous wave execution is the default).
  
  If execution produces NEEDS_DECISION: the gsd-execute-phase workflow
  surfaces it. Catch it and proceed to Step 2.2.
```

### Step 2.2: NEEDS_DECISION Resolution

When a phase hits an ambiguous design choice:

```
1. Extract the decision context from the executor's response
2. Dispatch gstack-decide subagent:
   Task dispatch:
     subagent: gstack-decide
     prompt: |
       Resolve design decision for Phase {N}.
       Decision context: {the unresolved choice with options}
       Phase ID: {N}
   
3. Receive JSON decision: { decision, selected_option, reasoning, confidence }
4. Log decision in phase.verdicts
5. Inject decision: re-dispatch the execution step with the decision included
6. Cap: max_decision_calls per phase before marking BLOCKED

Do NOT increment retries for decision calls.
```

### Step 2.3: Process Phase Result

| Result | Action |
|--------|--------|
| All waves complete, all plans done | Mark phase `completed`, increment `completed_count` |
| Partial completion (some plans failed) | Mark phase `failed`, increment `retries`. Will retry. |
| BLOCKED | Mark phase `failed`, increment `retries`, log reason. Will retry. |
| Retries exhausted (≥ max) | Mark phase `skipped`, log reason. Continue loop. |

### Step 2.4: Persist and Report

After each phase:
```
save build-loop.json
echo "Phase {N}/{total}: {name} — {status}"
echo "Progress: {completed_count}/{total_phases}"
```

### Step 2.5: Context Check

After each phase, check your own context usage. If approaching ~40%:
- Save build-loop.json
- Tell the user: "Context approaching budget. State saved. Resume with: build loop v2"
- Stop.

**Context cost: ~5% per phase** (wave summaries + verdicts, not plan content).

---

## PHASE 3: VERIFY (Multi-Layer)

**Goal:** Verify completed phases through structural, functional, and visual layers.

### Step 3.1: Structural Verification

For each completed phase:

```
Dispatch Task subagent with gsd-verify-work workflow.
Load the gsd-verify-work skill from `~/.config/opencode/skills/gsd-verify-work/SKILL.md`.

The verifier reads from disk:
- Phase goal from ROADMAP.md
- CONTEXT.md decisions
- PLAN.md acceptance criteria
- SUMMARY.md execution logs

It produces VERIFICATION.md with:
- Requirement coverage (REQ-IDs completed vs total)
- Decision coverage (CONTEXT.md decisions implemented)
- Goal alignment (does code deliver phase goal?)
- Fix plans for gaps

Return metadata: { reqs_covered, decisions_covered, gaps, fix_plans_created }
```

### Step 3.2: Functional QA (if enabled)

If `ralph_loop.verification.functional_qa == true` and `app_url` is configured:

```
Load the gstack QA skill from `~/.config/opencode/skills/gstack-qa/SKILL.md`.
Dispatch a subagent that:
- Opens the app at {app_url}
- Runs G-Stack QA browser-based testing
- Finds bugs, auto-fixes with atomic commits
- Generates regression tests per fix
- Returns: { bugs_found, bugs_fixed, regression_tests_added }

Use spawned/headless mode for no user interaction.
```

### Step 3.3: Design Review (if enabled)

If `ralph_loop.verification.design_review == true` and phase has UI:

```
Load the gstack design-review skill from `~/.config/opencode/skills/gstack-design-review/SKILL.md`.
Dispatch a subagent that:
- Captures before/after screenshots
- Runs visual audit against DESIGN.md
- Auto-fixes visual issues iteratively
- Returns: { visual_score, issues_found, issues_fixed }

Use spawned/headless mode for no user interaction.
```

### Step 3.4: Aggregate Verdicts

Update build-loop.json phase.verdicts with all verification results. Report summary.

**Context cost: ~5%** (aggregated verdicts only).

---

## PHASE 4: SHIP

**Goal:** Create PR, run pre-landing reviews, prepare for merge.

### Step 4.1: Create PR

For verified phases:

```
Load the gsd-ship skill from `~/.config/opencode/skills/gsd-ship/SKILL.md`.
Dispatch a subagent that:
- Creates a PR with rich body from planning artifacts
- PR body includes: phase goal, changes summary, requirements addressed,
  verification status, key decisions
- If auto_ship is false in config, creates draft PR
- Returns: { pr_url, pr_number, draft }
```

### Step 4.2: Pre-Landing Review

If `ralph_loop.shipping.require_review == true`:

```
Load the gstack review skill from `~/.config/opencode/skills/gstack-review/SKILL.md`.
Dispatch a subagent that:
- Reviews the PR diff for structural issues
- Auto-fixes obvious issues
- Flags completeness gaps
- Returns: { issues_found, auto_fixed, remaining }

Use spawned/headless mode.
```

### Step 4.3: Security Audit (if enabled)

If `ralph_loop.verification.security_audit == true`:

```
Load the gstack cso skill from `~/.config/opencode/skills/gstack-cso/SKILL.md`.
Dispatch a subagent that:
- Runs OWASP Top 10 + STRIDE threat model
- Zero-noise: 8/10+ confidence gate
- Returns: { findings, critical, high, medium }

Use spawned/headless mode.
```

### Step 4.4: Final Report

```
Write build-loop-report.md to ~/.gstack/projects/$SLUG/
Update build-loop.json with final status
Report:
  BUILD COMPLETE — All {N} phases successful.
  BUILD COMPLETE WITH CONCERNS — {N} phases done, {M} concerns logged.
  BUILD PARTIALLY COMPLETE — {N} phases done, {M} skipped.
```

**Context cost: ~3%**

---

## CRASH RECOVERY

### Resume Procedure

1. Re-run the `ralph-loop-v2` skill
2. Phase 0 detects `.planning/PROJECT.md` → skips intake
3. Read `.planning/STATE.md` for current progress
4. Read `build-loop.json` for last orchestrator state
5. Reconcile (`.planning/` wins if conflict)
6. Find first phase with status `pending` or `failed` (retries < max)
7. Resume loop from that phase

### Manual Override

To re-run a completed phase:
1. Edit `build-loop.json`: change phase `status` from `completed` to `pending`
2. Also revert downstream phases that depend on it
3. Re-run `ralph-loop-v2`

### State File Location

- Primary: `.planning/STATE.md`
- Secondary: `~/.gstack/projects/$SLUG/build-loop.json`
- Report: `~/.gstack/projects/$SLUG/build-loop-report.md`

---

## SESSION KIND BEHAVIOR

| Mode | Phase 0 | Phase 1 | Phase 1.5 | Phase 2 | Phase 3 | Phase 4 |
|------|---------|---------|-----------|---------|---------|---------|
| **interactive** | Ask for spec if missing | Show phases, ask to proceed | Show gate results, ask on failures | Report progress, surface NEEDS_DECISION | Show verdicts | Ask before ship |
| **headless/spawned** | Auto-search spec, BLOCKED if none | Auto-proceed | Auto-decide, auto-approve | Auto-execute, auto-decide | Auto-verify, skip UAT | Auto-ship (draft if configured) |

---

## ARCHITECTURE SUMMARY

```
  ORCHESTRATOR (this skill)
  Context: ~25% total, metadata only
  ═══════════════════════════════
  Phase 0 → gsd-new-project (subagent)
  Phase 1 → ralph-planner (subagent) → discuss → plan → metadata
  Phase 1.5 → gstack-gate (subagent) → eng/design review → verdict
  Phase 2 → gsd-execute-phase (subagent) → waves → TDD executors
            └─ NEEDS_DECISION → gstack-decide → inject → re-dispatch
  Phase 3 → gsd-verify-work + /qa + /design-review (subagents)
  Phase 4 → gsd-ship + /review + /cso (subagents)

  SHARED DISK (.planning/ + build-loop.json)
  ════════════════════════════════════════
  PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md
  phases/{N}/CONTEXT.md, RESEARCH.md, PLAN.md, SUMMARY.md, VERIFICATION.md
  build-loop.json (metadata only)
```
