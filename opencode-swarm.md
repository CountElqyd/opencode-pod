# 🐝 OpenCode Swarm Plugin — Complete Guide

> **GitHub:** [github.com/ZaxbyHub/opencode-swarm](https://github.com/ZaxbyHub/opencode-swarm)  
> **Awesome OpenCode:** [github.com/awesome-opencode/awesome-opencode](https://github.com/awesome-opencode/awesome-opencode)

---

## Table of Contents

1. [What is OpenCode Swarm?](#what-is-opencode-swarm)
2. [Installation](#installation)
3. [Architecture Overview](#architecture-overview)
4. [The 11 Architect Modes](#the-11-architect-modes)
5. [The 17-Step QA Pipeline](#the-17-step-qa-pipeline)
6. [Agent Roster](#agent-roster)
7. [Execution Modes](#execution-modes)
8. [Built-in Quality Tools](#built-in-quality-tools)
9. [Swarm vs Superpowers](#swarm-vs-superpowers)
10. [Pros & Cons](#pros--cons)
11. [When to Use / When to Skip](#when-to-use--when-to-skip)
12. [Configuration](#configuration)
13. [Commands Reference](#commands-reference)

---

## What is OpenCode Swarm?

**OpenCode Swarm** is a verification-gated, architect-led multi-agent plugin for OpenCode. It is **not** a free-for-all of parallel agents. Instead, it uses a **hub-and-spoke architecture** where a single architect orchestrates a team of specialized agents, each using a **different AI model** to catch different blind spots.

**Core Philosophy:** *Nothing ships until every gate passes.* Every task goes through a 17-step QA pipeline before the next task begins. Agents never mutate the codebase in parallel.

---

## Installation

### Prerequisites
- **Bun** (preferred) or Node.js with npm
- OpenCode CLI installed

### Install via Bun (Recommended)
```bash
bunx opencode-swarm install
```

### Install via npm
```bash
npm install -g opencode-swarm
opencode-swarm install
```

### What the installer does
- Registers the Swarm plugin with OpenCode
- Creates the default configuration
- Disables conflicting default agents (Build/Plan modes)
- Sets up the `.swarm/` directory structure

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    ARCHITECT (Orchestrator)                  │
│              Uses: anthropic/claude-sonnet-4                │
└──────────────────────┬────────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┬──────────────┐
        ▼              ▼              ▼              ▼
   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
   │ EXPLORER│   │  CODER  │   │ REVIEWER│   │  TESTER │
   │(scan &  │   │(one task│   │(different│   │(write & │
   │ graph)  │   │ at time)│   │  model)  │   │  run)   │
   └─────────┘   └─────────┘   └─────────┘   └─────────┘
        │              │              │              │
        └──────────────┴──────────────┴──────────────┘
                       │
              ┌────────┴────────┐
              ▼                 ▼
        ┌─────────┐      ┌─────────┐
        │ CRITIC  │      │  SME    │
        │(plan    │      │(domain  │
        │ review) │      │ expert) │
        └─────────┘      └─────────┘
```

### Key Design Principles

1. **Single Writer** — Only the coder mutates code, one task at a time
2. **Different Models** — Each agent uses a different model to catch different blind spots
3. **Gated Pipeline** — Every task passes 17 checks before proceeding
4. **Persistent State** — `.swarm/` directory survives session restarts
5. **Evidence-Based** — Every decision is serialized to `.swarm/evidence/`

---

## The 11 Architect Modes

The architect cycles through these modes automatically based on project state:

| # | Mode | Description |
|---|------|-------------|
| 1 | **RESUME** | Checks `.swarm/plan.md`. If exists, continues where left off. No repeated discovery. |
| 2 | **SPECIFY** | Generates feature specification with requirements and acceptance criteria. |
| 3 | **CLARIFY** | Asks you questions, but *only* what it cannot infer from the codebase. |
| 4 | **DISCOVER** | Explorer scans codebase + builds code graph. **CODEBASE REALITY CHECK** verifies every referenced item is actually in the current state. |
| 5 | **CONSULT** | SME agents provide domain guidance. Council may convene for architectural decisions. |
| 6 | **PLAN** | Architect writes phased implementation plan. Council deliberates on complex plans. |
| 7 | **CRITIC-GATE** | Sounding board + critic review the plan. Max 2 revision cycles. **Plan blocked until approved.** |
| 8 | **EXECUTE** | Tasks implemented one at a time through the 17-step QA pipeline. |
| 9 | **PHASE-COUNCIL** | Full-phase review at `phase_complete`. Separate from per-task gates. REJECT blocks phase completion. |
| 10 | **MUTATION-GATE** | *Optional.* Generates mutations for changed files, validates test suite catches them. FAIL blocks phase. |
| 11 | **PHASE-WRAP** | Docs update, retrospective written, curator consolidates knowledge, drift evidence verified. |

### Mode Flow Diagram

```
RESUME → SPECIFY → CLARIFY → DISCOVER → CONSULT → PLAN → CRITIC-GATE → EXECUTE
                                                                    ↓
                                                              (17-step pipeline)
                                                                    ↓
PHASE-WRAP ← MUTATION-GATE ← PHASE-COUNCIL ←────────────────────────┘
```

---

## The 17-Step QA Pipeline

Every single task goes through this pipeline. No exceptions. No shortcuts.

### Stage A: Automated Checks (Steps 1–8)

| Step | Check | Description |
|------|-------|-------------|
| 1 | **@coder** | Implements **ONE** task only, with code graph context |
| 2 | **Write authority** | Permission boundary enforcement |
| 3 | **diff + imports** | Contract + dependency analysis |
| 4 | **syntax_check** | Tree-sitter parse validation |
| 5 | **placeholder_scan** | Catches TODOs, FIXMEs, stubs |
| 6 | **lint fix → lint check** | Auto-fix then lint validation |
| 7 | **build_check** | Does it compile? |
| 8 | **pre_check_batch** | Parallel: lint + secretscan + SAST + quality budget (~15s) |

### Stage B: Agent Review (Steps 9–17) — *Always Runs*

| Step | Agent | Description |
|------|-------|-------------|
| 9 | **@hallucination_verifier** | API calls vs real sources |
| 10 | **@drift_verifier** | Spec divergence check |
| 11 | **PRM trajectory** | Mid-execution correction scoring |
| 12 | **@reviewer** | Correctness pass (**different model**) |
| 13 | **@reviewer** | Security pass (if needed) |
| 14 | **@test_engineer** | Verification tests + coverage ≥70% |
| 15 | **@test_engineer** | Adversarial tests |
| 16 | **post_check_batch** | Final lint + security + quality |
| 17 | **Evidence** | Serialized to `.swarm/evidence/{taskId}.json` |

### Closed-Loop Correction

If any gate fails, the task **loops back** to the coder with **structured feedback**:
- Syntax error location
- Placeholder found at line 42
- Reviewer concern about race condition
- Test failure trace

This is what makes Swarm reliable — not just "fix it," but *specific signals*.

---

## Agent Roster

### Core Agents (Always Active)

| Agent | Role | Model Strategy |
|-------|------|----------------|
| **architect** | Orchestrates workflow, writes plans, enforces gates | Primary orchestrator model |
| **explorer** | Scans codebase, builds code graph, maps facts | Fast exploration model |
| **coder** | Implements **one task at a time** | Strong coding model |
| **reviewer** | Correctness + security review | **Different model** than coder |
| **test_engineer** | Writes & runs tests, adversarial testing | Test-focused model |
| **critic** | Reviews plans before implementation | Critical analysis model |
| **critic_oversight** | Sole quality gate in Full-Auto mode | Safety model |
| **sme** | Domain expertise guidance | Domain-specific model |
| **docs** | Updates documentation | Documentation model |

### Optional Agents (On by Default)

| Agent | Role |
|-------|------|
| **critic_sounding_board** | Pre-escalation pushback to architect |
| **critic_drift_verifier** | Verifies implementation matches spec |
| **critic_hallucination_verifier** | Verifies APIs against real sources |
| **curator_init** | Consolidates prior knowledge at start |
| **curator_phase** | Consolidates phase outcomes |

### Conditional Agents (Config-Gated)

| Agent | Role | Gate |
|-------|------|------|
| **designer** | UI scaffolds & design tokens | `ui_review` enabled |
| **council_generalist** | Broad analytical voice | `council` enabled |
| **council_skeptic** | Adversarial stress-tester | `council` enabled |
| **council_domain_expert** | Technical depth voice | `council` enabled |

---

## Execution Modes

### Session Modes (Runtime)

| Mode | Safety | Speed | Description |
|------|--------|-------|-------------|
| **Balanced** | High | Medium | Default. All gates run. Everyday development. |
| **Turbo** | Medium | Fast | Skips Stage B gates for non-Tier-3 files. Rapid iteration. |
| **Lean Turbo** | High | Fast | Parallel lanes for non-conflicting tasks (up to `max_parallel_coders`). |
| **Full-Auto** | Deterministic | Fast | Unattended runs. Safe ops auto-allowed; risky ops routed through `critic_oversight`. |

### Project Modes (Persistent)

| Mode | Description |
|------|-------------|
| **strict** | Adds slop-detector + incremental-verify. Maximum safety. |
| **balanced** | Default project mode. Standard gates. |
| **fast** | Skips compaction. Speed over thoroughness. |

### Mode Commands

```bash
/swarm turbo on          # Enable turbo mode
/swarm turbo off         # Disable turbo mode
/swarm full-auto on      # Enable unattended mode
/swarm full-auto off     # Disable unattended mode
/swarm mode strict       # Set project to strict mode
/swarm mode balanced     # Set project to balanced mode
/swarm mode fast        # Set project to fast mode
```

---

## Built-in Quality Tools

All tools run **locally**. No Docker, no external APIs.

| Tool | Purpose | Frequency |
|------|---------|-----------|
| **syntax_check** | Tree-sitter validation across 12 languages | Every task |
| **placeholder_scan** | Catches TODOs, stubs, incomplete code | Every task |
| **sast_scan** | 65 security rules, 7 languages, offline | Every task |
| **sbom_generate** | CycloneDX dependency tracking | Phase wrap |
| **build_check** | Project-native build/typecheck | Every task |
| **incremental_verify** | Post-coder typecheck (TS/JS, Go, Rust, C#) | Strict mode |
| **quality_budget** | Complexity, duplication, test ratio limits | Every task |
| **pre_check_batch** | Parallel lint + secretscan + SAST + quality | Every task |
| **mutation_test** | LLM-generated mutation patches, kill rate scoring | Optional phase gate |
| **git_blame** | Per-line git blame metadata | On demand |

---

## Swarm vs Superpowers

### Architecture Comparison

| Dimension | 🐝 Swarm | ⚡ Superpowers |
|-----------|---------|---------------|
| **Orchestration** | Architect-led hub-and-spoke | Skills-driven workflow |
| **Parallelism** | Single writer (Lean Turbo allows parallel lanes) | Fresh subagent per task |
| **Test Strategy** | Tests written **after** code (test engineer gate) | **TDD-first** — failing tests before production code |
| **Model Strategy** | Multi-model by design (different model per agent) | Single model (configurable) |
| **Plan Review** | Critic-gate with max 2 revision cycles | Design approval, less rigid |
| **Context Management** | Context Budget Guard (warns at 70%, critical at 90%) | Token-conscious but no formal guard |
| **State Persistence** | Full `.swarm/` directory with plans, evidence, telemetry | Plan persistence, no structured evidence |
| **Security** | Built-in SAST (65 rules), secretscan, SBOM, adversarial tests | Basic security review skill |
| **Knowledge System** | Two-tier: project-level + org-level with auto-promotion | No formal knowledge capture |
| **Mutation Testing** | Optional gate with kill rate scoring | Not available |
| **Code Graph** | Built-in repo graph with incremental updates | No structural awareness |
| **Observability** | Structured telemetry (`telemetry.jsonl`) | No structured logging |
| **Skills Ecosystem** | External skill curation (3-gate validation, disabled by default) | Rich skill library (20+ official skills) |
| **Human Checkpoints** | Gate-based auto-proceed | Explicit approvals at each phase |
| **Best For** | Production code, brownfield, security-critical, audit trails | Greenfield, learning TDD, rapid prototyping |

### Workflow Diagrams

**Swarm:**
```
DISCOVER → PLAN → CRITIC-GATE → CODER → AUTO → REVIEWER → TESTER
   ↑___________________________________________________________↓
   └─────────────────── (next task) ───────────────────────────┘
```

**Superpowers:**
```
BRAINSTORM → SPEC → PLAN → FAIL TEST → SUBAGENT → REVIEW → FINALIZE
```

---

## Pros & Cons

### ✅ Pros

1. **Catches different blind spots** — Reviewer uses a different model than coder. Architect uses another. Multi-perspective review is architecturally designed to catch what a single model misses.
2. **Nothing ships untested** — The 17-step pipeline is enforced, not optional.
3. **Resumable by design** — `.swarm/` contains everything: plans, evidence, knowledge, telemetry. Pick up any project after weeks.
4. **Production-grade security** — SAST (65 rules), secretscan, SBOM, adversarial tests, mutation testing — all offline.
5. **Structured observability** — `telemetry.jsonl` gives audit trails, dashboards, and debugging data.
6. **Context pressure management** — Budget guard prevents the architect from drowning in its own injected context.
7. **Knowledge compounds** — Hive-level knowledge auto-promotes lessons across projects. Your swarm literally learns.
8. **Full-Auto for CI/CD** — Unattended runs with deterministic policy + critic oversight. Can run in headless loops overnight.

### ❌ Cons

1. **Slower than vibe coding** — 17 gates per task means minutes, not seconds.
2. **Single writer bottleneck** — Only one coder writes at a time (Lean Turbo allows parallel lanes with constraints).
3. **Overkill for small tasks** — Fixing a typo through a 17-step pipeline is absurd.
4. **Requires Bun** — Installation requires Bun. npm fallback exists but is second-class.
5. **Steep learning curve** — 18 agents, 11 modes, 4 session modes, config files, evidence directory.
6. **Not TDD-first** — Tests are written *after* code by the test engineer. If you believe in strict TDD, this feels backwards.
7. **Can be expensive** — Multiple models per task = multiple API calls per task.
8. **Conflicts with default agents** — Swarm disables default Build/Plan modes. If you forget to select the Swarm architect, "nothing happens."
9. **Mutation testing is expensive** — Generates 5-10 mutations per function. Can significantly extend phase time.

---

## When to Use / When to Skip

### 🎯 Use Swarm When...

| Scenario | Why Swarm Wins |
|----------|----------------|
| Security-critical features (auth, payments, crypto) | SAST + secretscan + adversarial tests + different-model review = defense in depth |
| Brownfield refactoring | Code graph + reality check + regression sweep prevents breaking existing code |
| Team environments needing audit trails | Telemetry + evidence serialization + SBOM = compliance-ready |
| Long-running projects (weeks/months) | Resumable state + knowledge promotion = continuity |
| CI/CD automation | Full-Auto mode with deterministic policy + critic oversight |
| Catching subtle bugs | Different-model reviewer catches what the coder missed |

### 🚫 Skip Swarm When...

| Scenario | Better Alternative |
|----------|-------------------|
| Quick exploration / "find where X is defined" | Native `@explore` or `@scout` subagent |
| Single typo fix or one-liner | Default OpenCode Build mode |
| Strict TDD believer | Superpowers — failing tests first |
| Rapid prototyping / vibe coding | Superpowers brainstorming → plan, or default Build mode |
| Learning / experimenting with AI coding | Superpowers — simpler mental model, explicit human checkpoints |
| Tight token budget | Superpowers — plans first to save tokens, single model |

---

## Configuration

### Global Config (`~/.config/opencode/opencode-swarm.json`)

```json
{
  "agents": {
    "architect": {
      "model": "anthropic/claude-sonnet-4-20250514"
    },
    "coder": {
      "model": "minimax-coding-plan/MiniMax-M2.5"
    },
    "reviewer": {
      "model": "zai-coding-plan/glm-5"
    },
    "test_engineer": {
      "model": "minimax-coding-plan/MiniMax-M2.5"
    },
    "explorer": {
      "model": "google/gemini-2.5-flash"
    }
  },
  "session_mode": "balanced",
  "project_mode": "balanced",
  "max_parallel_coders": 2,
  "council": true,
  "ui_review": true,
  "mutation_testing": false
}
```

### Project Override (`.opencode/opencode-swarm.json`)

Place in your project root to override global settings for that project only.

### Key Settings

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `session_mode` | string | `"balanced"` | Runtime mode: balanced, turbo, lean_turbo, full_auto |
| `project_mode` | string | `"balanced"` | Persistent mode: strict, balanced, fast |
| `max_parallel_coders` | number | `1` | Max parallel lanes in Lean Turbo |
| `council` | boolean | `false` | Enable council deliberation agents |
| `ui_review` | boolean | `false` | Enable designer agent for UI tasks |
| `mutation_testing` | boolean | `false` | Enable mutation testing gate |

---

## Commands Reference

### Swarm Commands

```bash
/swarm help              # Show all available commands
/swarm agents            # List active agents and their models
/swarm status            # Current mode, phase, task count, gate status
/swarm evidence          # Show evidence for recent tasks
/swarm turbo on/off      # Toggle turbo mode
/swarm full-auto on/off  # Toggle unattended mode
/swarm mode <mode>       # Set project mode (strict/balanced/fast)
```

### Native OpenCode Commands (Work with Swarm)

```bash
@reviewer review auth.ts          # Manual reviewer invocation
@explorer map codebase            # Manual explorer invocation
@tester write tests for api.ts    # Manual test engineer invocation
```

---

## The `.swarm/` Directory Structure

```
.swarm/
├── plan.md              # Current implementation plan
├── evidence/            # Serialized evidence per task
│   ├── task-001.json
│   └── task-002.json
├── knowledge.jsonl      # Project-level knowledge
├── telemetry.jsonl      # Structured event logs
├── code-graph.json      # Incremental codebase graph
└── retrospective.md     # Phase retrospectives
```

---

## Bottom Line

**Swarm is a verification-gated factory** optimized for reliability, auditability, and catching errors. **Superpowers is a discipline-enforcing coach** optimized for methodical planning and TDD.

Many teams use **both**: Superpowers for the initial spec and plan, Swarm for the execution and verification phases.

**Start with Swarm when:** you're building production code that can't break, working in a team, or need audit trails.  
**Start with Superpowers when:** you're learning, prototyping, or need strict TDD discipline.

---

*Generated from the awesome-opencode ecosystem research.*
