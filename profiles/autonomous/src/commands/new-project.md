---
description: Bootstrap a NEW project with graphify token-savings + superpowers memory
---

You are bootstrapping this directory as a NEW project for maximum token efficiency.
Follow ALL steps in order. This is a brand-new project, so nothing is set up yet.

1. **git init** — if no git repo exists, run `git init`. If one exists, skip.

2. **Build the graph** — load the `graphify` skill and run its full pipeline on the
   current directory (default mode). Do NOT pass `--mode deep`. Code-only corpora
   are AST-extracted and cost zero tokens. If the pipeline fails on an empty graph,
   still continue with steps 3-6 and note in your summary that the graph is empty.
   If the build errors on a missing LLM API key (a doc file is present and no
   GEMINI_API_KEY is set), re-run with `--code-only` and continue, noting in the
   summary that docs were not semantically embedded.

3. **Freshness hook** — run `graphify hook install` so the graph auto-rebuilds
   (AST-only, zero tokens) after every commit. If it fails (not a git repo), report
   it and continue.

4. **AGENTS.md "Graphify First" contract** — create `AGENTS.md` in the project
   root, or append to it if it exists (never clobber). Append exactly the section
   below, with no leading indentation:

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

5. **Superpowers memory** — load the `context-management` skill and generate
   `project-map.md` and `session-log.md` (create new; do not skip if they exist —
   update them if present).

6. **Summary** — print: graph stats (nodes/edges/communities), the list of files
   created/modified, and remind the user that `/graphify query "<question>"` is now
   their primary codebase-question tool.
