---
name: build-loop
description: |
  Autonomous route loop orchestrator that combines G-Stack (role-based spec review),
  GSD (phase decomposition to prevent context rot), and Superpowers (TDD execution)
  into a single pipeline. Breaks a spec into independent phases, dispatches each
  phase to a fresh subagent context, and iterates until the project is fully built.
  Fully autonomous with resumable state — can run overnight.
  Use when asked to "build loop", "route loop", "autonomous build", "build it all",
  "run the full pipeline", or "execute this spec end-to-end".
  Proactively suggest when the user has a spec/plan they want built autonomously.
triggers:
  - build loop
  - route loop
  - autonomous build
  - build it all
  - ralph loop
  - execute spec
  - run pipeline
compatibility: opencode
license: MIT
---

## Preamble (run first)

```bash
_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
GSTACK_ROOT="$HOME/.gbrain/skills/gstack"
[ -n "$_ROOT" ] && [ -d "$_ROOT/.gbrain/skills/gstack" ] && GSTACK_ROOT="$_ROOT/.gbrain/skills/gstack"
GSTACK_BIN="$GSTACK_ROOT/bin"
_UPD=$($GSTACK_BIN/gstack-update-check 2>/dev/null || .gbrain/skills/gstack/bin/gstack-update-check 2>/dev/null || true)
[ -n "$_UPD" ] && echo "$_UPD" || true
mkdir -p ~/.gstack/sessions
touch ~/.gstack/sessions/"$PPID"
_SESSIONS=$(find ~/.gstack/sessions -mmin -120 -type f 2>/dev/null | wc -l | tr -d ' ')
find ~/.gstack/sessions -mmin +120 -type f -exec rm {} + 2>/dev/null || true
_PROACTIVE=$($GSTACK_BIN/gstack-config get proactive 2>/dev/null || echo "true")
_PROACTIVE_PROMPTED=$([ -f ~/.gstack/.proactive-prompted ] && echo "yes" || echo "no")
_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
echo "BRANCH: $_BRANCH"
_SKILL_PREFIX=$($GSTACK_BIN/gstack-config get skill_prefix 2>/dev/null || echo "false")
echo "PROACTIVE: $_PROACTIVE"
echo "PROACTIVE_PROMPTED: $_PROACTIVE_PROMPTED"
echo "SKILL_PREFIX: $_SKILL_PREFIX"
source <($GSTACK_BIN/gstack-repo-mode 2>/dev/null) || true
REPO_MODE=${REPO_MODE:-unknown}
echo "REPO_MODE: $REPO_MODE"
_SESSION_KIND=$($GSTACK_BIN/gstack-session-kind 2>/dev/null || echo "interactive")
case "$_SESSION_KIND" in spawned|headless|interactive) ;; *) _SESSION_KIND="interactive" ;; esac
echo "SESSION_KIND: $_SESSION_KIND"
_LAKE_SEEN=$([ -f ~/.gstack/.completeness-intro-seen ] && echo "yes" || echo "no")
echo "LAKE_INTRO: $_LAKE_SEEN"
_TEL=$($GSTACK_BIN/gstack-config get telemetry 2>/dev/null || true)
_TEL_PROMPTED=$([ -f ~/.gstack/.telemetry-prompted ] && echo "yes" || echo "no")
_TEL_START=$(date +%s)
_SESSION_ID="$$-$(date +%s)"
echo "TELEMETRY: ${_TEL:-off}"
echo "TEL_PROMPTED: $_TEL_PROMPTED"
_EXPLAIN_LEVEL=$($GSTACK_BIN/gstack-config get explain_level 2>/dev/null || echo "default")
if [ "$_EXPLAIN_LEVEL" != "default" ] && [ "$_EXPLAIN_LEVEL" != "terse" ]; then _EXPLAIN_LEVEL="default"; fi
echo "EXPLAIN_LEVEL: $_EXPLAIN_LEVEL"
_QUESTION_TUNING=$($GSTACK_BIN/gstack-config get question_tuning 2>/dev/null || echo "false")
echo "QUESTION_TUNING: $_QUESTION_TUNING"
eval "$($GSTACK_BIN/gstack-slug 2>/dev/null)" 2>/dev/null || true
SLUG=${SLUG:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null | tr -cd 'a-zA-Z0-9._-' || echo "unknown")}
mkdir -p ~/.gstack/analytics
if [ "$_TEL" != "off" ]; then
echo '{"skill":"build-loop","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","repo":"'"$SLUG"'"}'  >> ~/.gstack/analytics/skill-usage.jsonl 2>/dev/null || true
fi
for _PF in $(find ~/.gstack/analytics -maxdepth 1 -name '.pending-*' 2>/dev/null); do
  if [ -f "$_PF" ]; then
    if [ "$_TEL" != "off" ] && [ -x "$GSTACK_BIN/gstack-telemetry-log" ]; then
      $GSTACK_BIN/gstack-telemetry-log --event-type skill_run --skill _pending_finalize --outcome unknown --session-id "$_SESSION_ID" 2>/dev/null || true
    fi
    rm -f "$_PF" 2>/dev/null || true
  fi
  break
done
echo "SESSION_ID: $_SESSION_ID"
echo "SLUG: $SLUG"

# State directory and file
_STATE_DIR="${GSTACK_HOME:-$HOME/.gstack}/projects/$SLUG"
_STATE_FILE="$_STATE_DIR/build-loop.json"
mkdir -p "$_STATE_DIR"
echo "STATE_FILE: $_STATE_FILE"
echo "---"
```

## /build-loop: Autonomous Route Loop Orchestrator

### What This Is

The build loop combines three spectrum development frameworks into one autonomous pipeline:

| Framework | Role in the Loop | Installed |
|-----------|-----------------|-----------|
| **G-Stack** | Spec review & decision-making (CEO/Eng/Design personas vote on design choices) | Yes |
| **GSD** | Phase decomposition to prevent context rot (each phase stays under ~40% context) | Built into this skill |
| **Superpowers** | TDD execution via subagents (RED-GREEN-REFACTOR cycle per phase) | Yes |

The orchestrator stays clean (target: under 10% context usage). All real work happens in fresh subagent sessions. This means accuracy stays high through hundreds of background sessions — no context rot.

### The Iron Law

**The orchestrator never writes production code.** It delegates everything. Its job is coordination: read state, dispatch subagents, update state, repeat. If you find yourself implementing something as the orchestrator, STOP — that's a subagent's job.

### State File

All progress lives in a resumable JSON state file:

**Location:** `~/.gstack/projects/$SLUG/build-loop.json`

**Schema:**
```json
{
  "project": "my-app",
  "spec": "# Full specification...",
  "spec_source": "path/to/spec.md or 'inline'",
  "phases": [
    {
      "id": 1,
      "name": "Data models and migrations",
      "description": "Create all database models, migrations, and schema",
      "prompt": "Full prompt for the subagent...",
      "files": ["src/models/", "migrations/"],
      "dependencies": [],
      "status": "pending",
      "result": null,
      "retries": 0,
      "started_at": null,
      "completed_at": null
    }
  ],
  "completed_count": 0,
  "total_phases": 0,
  "created_at": "",
  "last_updated": ""
}
```

**Status values:** `pending` | `in_progress` | `completed` | `failed` | `skipped`

### Execution Phases

---

## PHASE 0: INTAKE — Load or Create the Spec

**Goal:** Get a specification to build from. If a spec file already exists, load it. If not, use G-Stack to create one.

### Step 0.1: Check for existing state

```bash
Read the state file at $_STATE_FILE if it exists.
```

If the state file exists and has phases with `status: "pending"` or `status: "in_progress"`, SKIP to Phase 2 (Route Loop) — resume execution.

If the state file exists and all phases are `completed`, report: "Build loop already completed. To re-run, delete the state file or use --force."

### Step 0.2: Locate the spec

If the user provided a file path with the command (e.g., `/build-loop docs/specs/my-app.md`), use that path directly. Verify the file exists. If it does, load its contents and skip to Step 0.4.

If the user provided an idea description instead of a file (e.g., `/build-loop "A todo app with auth"`), treat it as an inline idea and proceed to Step 0.3 to create a spec from it using G-Stack.

If no path or idea was provided:
- In `interactive` mode, ask the user for the spec/plan file path or idea description.
- In `spawned` or `headless` mode, search for common spec locations:
  - `docs/superpowers/specs/*-design.md`
  - `docs/superpowers/plans/*.md`
  - `SPEC.md`, `PLAN.md`, `DESIGN.md` at repo root
  - `~/.gstack/projects/$SLUG/ceo-plans/*.md`

If no spec found and in `spawned`/`headless` mode, report BLOCKED: "No spec file found. Provide a spec file path."

If no spec found and in `interactive` mode, ask the user: "No spec found. Create one using G-Stack brainstorming, or provide a path to an existing spec?"

### Step 0.3: If creating a new spec

Use G-Stack's pipeline to create and review the spec:

1. Run `/office-hours` (builder mode) to clarify the product vision — saves a design doc
2. Run `/plan-ceo-review` on the design doc — scope, strategy, ambition
3. Run `/plan-eng-review` on the design doc — architecture, data flow, test plan
4. Run `/plan-design-review` if there's a UI component

Wait for the user to approve the finalized spec before proceeding.

### Step 0.4: Initialize the state file

Once the spec is confirmed, create the state file with:
- `project` from the slug
- `spec` containing the full spec text
- `spec_source` set to the file path
- Empty `phases` array
- `created_at` timestamp

Save it. Report: "State file initialized. Moving to Phase 1: Decomposition."

---

## PHASE 1: GSD DECOMPOSITION — Break the Spec into Phases

**Goal:** Decompose the spec into ordered, independent phases where each phase's prompt fits under ~40% of the context window. This prevents context rot.

### Decomposition Rules

1. **Dependency ordering:** Phases are ordered so each phase only depends on completed phases.
   - Models/DB schema first
   - Services/business logic second
   - API/controllers third
   - Frontend/UI last

2. **Context budget:** Each phase prompt must stay under ~40% of context. If a phase would be too large, split it further. Target: each phase is 1-3 files to create/modify.

3. **File boundaries:** Phases respect file boundaries. A phase should never partially create a file — files are owned by exactly one phase.

4. **Max phases:** Hard cap at 15 phases. If decomposition would produce more, merge the smallest leaf phases.

5. **Independence:** Phases should be as independent as possible within dependency ordering. Two phases that don't depend on each other can be swapped.

### Phase Prompt Format

Each phase prompt must be self-contained (the subagent gets NO context from the orchestrator):

```
You are a build executor subagent. Your job is to implement Phase N: [name].

CONTEXT: This is part of a {total_phases}-phase build for project "{project}".

WHAT ALREADY EXISTS (from completed phases):
- {list files/directories created by prior phases}

WHAT YOU MUST BUILD:
{detailed description from the spec — the subagent needs everything here}

TECH STACK: {languages, frameworks, libraries}

FILES TO CREATE:
- {exact file paths}

FILES TO MODIFY:
- {exact file paths with line ranges}

TDD REQUIREMENT:
You MUST follow the Superpowers TDD cycle for EVERY piece of code:
1. Write a failing test first
2. Verify the test FAILS (feature missing)
3. Write minimal code to pass
4. Verify the test PASSES
5. Refactor if needed

VERIFICATION:
After implementation, run these commands to verify:
- {exact test/verify commands}

STATUS CODE:
When done, report one of:
- DONE: All work complete, all tests pass
- DONE_WITH_CONCERNS: Work done but {specific concern}
- BLOCKED: Cannot proceed because {specific blocker}
- NEEDS_DECISION: Hit a design choice. Describe the options with trade-offs.

NEVER ask the user questions. If you hit a design decision, report NEEDS_DECISION with a clear description of the options.
```

### Step 1.1: Analyze the spec

Read the spec in full. Identify:
- All components, modules, files mentioned
- Dependencies between them
- Tech stack components
- Test requirements

### Step 1.2: Create the phase list

For each phase, specify:
- `id`: sequential number
- `name`: short descriptive name
- `description`: what this phase builds
- `prompt`: the full self-contained subagent prompt (following the format above)
- `files`: files this phase creates/modifies
- `dependencies`: phase IDs this depends on

### Step 1.3: Write to state file

Update `$_STATE_FILE` with the phase list. Set `total_phases`. Set all phases to `status: "pending"`. Report the phase breakdown to the user.

In `interactive` mode, show the phases and ask: "Proceed with build queue? (y/n)"

In `spawned`/`headless` mode, proceed automatically.

---

## PHASE 2: ROUTE LOOP — Execute Phase by Phase

**Goal:** Iterate through phases, dispatching each to a fresh subagent, tracking progress in the state file.

**This is the core loop. The orchestrator stays clean — it delegates everything.**

### Loop Algorithm

```
load state from $_STATE_FILE

while true:
  # Find next pending/incomplete phase
  next = first phase where status is "pending" or (
    status is "failed" and retries < 3
  )

  if next is None:
    break  # all phases done or all failures exhausted

  # Mark in progress
  next.status = "in_progress"
  next.started_at = now()
  save state

  # Dispatch subagent
  result = dispatch build-executor subagent with next.prompt

  # Process result
  if result is "DONE":
    next.status = "completed"
    next.retries unchanged
    next.result = "All tests pass, implementation complete"
    completed_count += 1

  elif result is "DONE_WITH_CONCERNS":
    next.status = "completed"
    next.result = "DONE_WITH_CONCERNS: " + concerns
    completed_count += 1
    # Log concerns but continue — don't block the loop

  elif result is "BLOCKED":
    next.status = "failed"
    next.retries += 1
    next.result = "BLOCKED: " + reason
    # Will retry up to 2 more times before skipping

  elif result contains "NEEDS_DECISION":
    # G-Stack auto-decides the design question
    Run G-Stack role-based review on the decision point:
      1. Dispatch a subagent running /plan-eng-review focused on the decision
      2. Collect the recommendation
    Save the decision in phase result
    # Re-dispatch the same phase with the decision injected
    Reprompt the subagent with: "CONTEXT DECISION: {decision}. Now proceed."
    # Don't increment retries for decision calls
    continue  # re-execute same phase

  else:
    next.status = "failed"
    next.retries += 1
    next.result = "UNEXPECTED: " + result

  # If failed and retries exhausted
  if next.status == "failed" and next.retries >= 3:
    next.status = "skipped"
    next.result = "SKIPPED after 3 failures: " + next.result
    # Report to user but continue the loop

  # Persist state after every phase
  next.completed_at = now() (if done)
  save state

  # Report progress
  echo "Phase {next.id}/{total_phases}: {next.name} — {next.status}"
  echo "Progress: {completed_count}/{total_phases} complete"

# After loop
Go to Phase 3: Final Gate
```

### Subagent Dispatch

Use OpenCode's `Task` tool with `subagent_type: "general"`. The subagent must be told:
- Its task is the phase prompt exactly as written
- It must NOT read skill files or state files
- It must return exactly one status code
- It has edit and bash permissions

### G-Stack Decision Integration

When the subagent returns `NEEDS_DECISION`:

1. The decision is a design/architecture choice the subagent can't resolve alone
2. The orchestrator dispatches a **decision subagent** that uses G-Stack's role-based review:
   - Loads `/plan-eng-review` for architecture decisions
   - Loads `/plan-design-review` for UI/UX decisions
   - Loads `/plan-ceo-review` for scope/product decisions
   - Auto-decides using G-Stack's 6 decision principles (completeness, boil lakes, pragmatic, DRY, explicit, bias-toward-action)
3. The decision is injected back into the phase prompt
4. The same phase is re-dispatched

The orchestrator tracks how many times each phase hits a decision (cap: 5 decision calls before marking BLOCKED).

### Context Rot Prevention

The orchestrator verifies after each phase:
- Read the state file and check how much context has been consumed
- If the orchestrator's context approaches ~40%, save a checkpoint: write the current state, tell the user to resume from this point in a fresh session

---

## PHASE 3: FINAL GATE — Verification and Report

**Goal:** After all phases complete (or fail), run final verification and produce a summary.

### Step 3.1: Final verification

Run these commands from the project root:
- Test suite: locate and run (pytest, npm test, cargo test, etc.)
- Linter: locate and run
- Build: locate and run (if applicable)
- Type checker: locate and run (if applicable)

Report results with exit codes and failure counts.

### Step 3.2: Generate the summary report

```
╔══════════════════════════════════════════════╗
║           BUILD LOOP — FINAL REPORT          ║
╠══════════════════════════════════════════════╣
║ Project:     {project}                       ║
║ Spec:        {spec_source}                   ║
║ Total Phases:{total_phases}                  ║
║                                              ║
║ COMPLETED:   {count}                         ║
║ FAILED:      {count}                         ║
║ SKIPPED:     {count}                         ║
╠══════════════════════════════════════════════╣
║ PHASE STATUS:                                ║
║                                              ║
║ {phase_id} [{status_icon}] {name}            ║
║   {result}                                   ║
║ ...                                          ║
╠══════════════════════════════════════════════╣
║ VERIFICATION:                                ║
║ Tests:   {pass}/{total}                      ║
║ Linter:  {pass/fail}                         ║
║ Build:   {pass/fail}                         ║
║ Type:    {pass/fail}                         ║
╚══════════════════════════════════════════════╝
```

### Step 3.3: Final state

- If ALL phases completed and verification passes: report "BUILD COMPLETE — All {n} phases successful."
- If DONE_WITH_CONCERNS: report "BUILD COMPLETE WITH CONCERNS — See phase details above."
- If any BLOCKED/SKIPPED: report "BUILD PARTIALLY COMPLETE — {n} phases failed. State file preserved for resumption."
- Write the final report to `$_STATE_DIR/build-loop-report.md`

### Step 3.4: Suggest next steps

If build complete: suggest running `/ship` to create a PR.
If partially complete: suggest addressing BLOCKED phases first, then re-running `/build-loop` to resume.

---

## Session Kind Behavior

| Mode | Phase 0 | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|---------|
| **interactive** | Ask for spec path | Show phases, ask to proceed | Report progress, ask on decisions | Show final report |
| **spawned** | Auto-search for spec, BLOCKED if none | Auto-proceed | Auto-decide everything | Auto-report |
| **headless** | Auto-search, BLOCKED if none | Auto-proceed | Auto-decide | Auto-report, output to terminal |

## Subagent Configuration

The build loop requires a `build-executor` subagent. Define it as a markdown file at `~/.config/opencode/agents/build-executor.md`:

```yaml
---
description: Executes a single build phase using Superpowers TDD. Reports DONE, DONE_WITH_CONCERNS, BLOCKED, or NEEDS_DECISION.
mode: subagent
hidden: true
steps: 30
permission:
  edit: allow
  bash: allow
  webfetch: deny
---
```

The markdown file name becomes the agent name (`build-executor`). The `hidden: true` keeps it out of the `@` autocomplete — it's programmatic-only, invoked by the orchestrator via the Task tool.

---

## State File Resilience

The state file is written to disk after EVERY phase transition. This means:
- If the session crashes, re-running `/build-loop` picks up where it left off
- If a subagent times out, the phase is marked `failed` and retried
- If the orchestrator hits context limits, save checkpoint and resume in fresh session

### Recovery Procedure

If the build loop is interrupted:
1. Re-run `/build-loop` in a fresh session
2. Phase 0 detects the existing state file with incomplete phases
3. The loop resumes from the first `pending` or `failed` phase
4. Completed phases are NOT re-executed

### Manual Override

To force re-run of a completed phase:
1. Edit `$_STATE_FILE`
2. Change the phase's `status` from `completed` to `pending`
3. Re-run `/build-loop`

---

## Decision Principles (for G-Stack integration)

When auto-deciding design questions, apply G-Stack's 6 principles:

1. **Completeness:** Ship the whole thing. Cover more edge cases.
2. **Boil lakes:** Fix everything in the blast radius. Auto-approve if < 1 day effort.
3. **Pragmatic:** If two options fix the same thing, pick the cleaner one. 5 seconds, not 5 minutes.
4. **DRY:** Reject duplicates. Reuse what exists.
5. **Explicit over clever:** 10-line obvious fix > 200-line abstraction.
6. **Bias toward action:** Merge > review cycles > stale deliberation.

Conflict resolution:
- Architecture/engineering questions: P5 + P3 dominate
- UI/design questions: P5 + P1 dominate
- Scope/feature questions: P1 + P2 dominate

---

## File Manifest

Files this skill creates/writes to:

| File | Purpose |
|------|---------|
| `~/.gstack/projects/$SLUG/build-loop.json` | Resumable state tracking phase completion |
| `~/.gstack/projects/$SLUG/build-loop-report.md` | Final report after all phases complete |
| `~/.gstack/analytics/skill-usage.jsonl` | Telemetry (if enabled) |
| `~/.gstack/sessions/$PPID` | Session marker (120-min TTL) |

---

## Summary

```
┌─────────────────────────────────────────────────────┐
│  /build-loop: Autonomous Route Loop                  │
│                                                      │
│  INPUT  → Spec file (or create via G-Stack)          │
│                                                      │
│  STEP 1 → GSD: Decompose spec into ≤15 phases        │
│           Each phase fits under 40% context          │
│                                                      │
│  STEP 2 → Route Loop: For each phase:                │
│           ┌─ Dispatch subagent (fresh context)       │
│           ├─ Subagent follows Superpowers TDD        │
│           ├─ If NEEDS_DECISION → G-Stack auto-decide │
│           ├─ Mark phase done/failed                  │
│           └─ Save state, continue                    │
│                                                      │
│  STEP 3 → Final Gate: Run full test suite, linter,   │
│           build. Report results.                     │
│                                                      │
│  OUTPUT → Fully built project + final report         │
│           All state preserved for resumption          │
└─────────────────────────────────────────────────────┘
```
