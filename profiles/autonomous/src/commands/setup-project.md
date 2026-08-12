---
description: Configure an EXISTING project with graphify token-savings (idempotent)
---

You are configuring this EXISTING project for maximum token efficiency. Follow ALL
steps in order. Do NOT run `git init`.

1. **Git check** — if this directory is NOT a git repo, print a warning: "Not a git
   repo — the post-commit freshness hook requires git and will be skipped. You can
   git init later and re-run /setup-project." Then CONTINUE with steps 2-6 anyway
   (do not abort).

2. **Build or update the graph** — load the `graphify` skill:
   - If `graphify-out/graph.json` already exists: run the skill in `--update` mode
     (incremental re-extraction of changed files; preserves manual labels). Do NOT
     do a full rebuild.
   - Otherwise (fresh build): run the full pipeline on the current directory in
     standard mode. Use `--mode deep` ONLY if the user included `deep` in the
     command invocation ($ARGUMENTS); never ask, never wait.
   - If a build or update errors on a missing LLM API key (doc files present, no
     GEMINI_API_KEY set), re-run with `--code-only` and continue; note in the
     summary that docs were not semantically embedded.

3. **Freshness hook** — run `graphify hook install`. It appends to an existing
   post-commit hook rather than replacing it. If it fails (not a git repo), report
   it and continue.

4. **AGENTS.md "Graphify First" contract (idempotent)** — check whether
   `AGENTS.md` in the project root already contains a `## Graphify First` heading.
   If yes, SKIP and note "already configured". If no, append exactly the section
   below, with no leading indentation (never clobber existing content):

   ```markdown
   ## Graphify First

   - If `graphify-out/graph.json` exists, answer codebase questions with
     `graphify query "<question>" --budget 1500` instead of reading raw files.
   - Read `graphify-out/GRAPH_REPORT.md` for architecture context (god nodes,
     communities).
   - Fall back to reading source files ONLY when the graph cannot answer; quote
     `source_location` when citing a fact from the graph.
   - After large manual changes, run `graphify update .` if the post-commit hook
     has not caught up.
   ```

5. **Superpowers memory** — load the `context-management` skill. If
   `project-map.md` / `session-log.md` exist, update them (staleness-aware); create
   them only if absent.

6. **Summary** — print graph stats (nodes/edges/communities) and a diff-style
   report: what was set up NOW vs what was already in place (e.g. "AGENTS.md:
   skipped (already present)", "graph: updated incrementally", "hook: installed").
