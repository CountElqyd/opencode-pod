---
description: Launch a zero-interruption autonomous coding session inside the opencode-pod container using the autonomous profile and GSD /gsd-autonomous.
argument-hint: "[--watch] [--timeout 4h]"
effort: max
requires: [cleanup, phase, progress]
tools:
  read: true
  write: true
  bash: true
  glob: true
  grep: true
---
<objective>
Launch a zero-interruption autonomous coding session inside the isolated opencode-pod container for this project. Boot the container with the `autonomous` profile (installing it if needed), then trigger GSD's `/gsd-autonomous` inside the container's opencode. No questions, no pauses — ship when done.
</objective>

<context>
Flags:
- `--watch` — monitor progress via git commits/logs instead of reporting only at completion.
- `--timeout 4h` — hard kill the session after the given duration (default 4h).

Preconditions (fail fast):
1. `docs/planning/design-doc.md` exists and is marked locked.
2. `graphify-out/graph.json` is fresh (newer than the design doc mtime).
3. Rootless podman + opencode-pod are installed on the host.

The `autonomous` profile is a pinned release tarball — installing it is idempotent and SHA256-verified. It must already be registered in `profiles/index.json` of the opencode-pod repo.
</context>

<process>
1. Validate preconditions:
   - `test -f docs/planning/design-doc.md` else abort with message.
   - `test -f graphify-out/graph.json` else abort; if stale, tell user to re-run `graphify build`.
2. Ensure the profile is installed (idempotent):
   ```bash
   cd <project> && opencode-pod profile install autonomous
   ```
3. Start/attach the container:
   ```bash
   cd <project> && opencode-pod start
   ```
4. Trigger the autonomous session inside the container:
   ```bash
   podman exec -u dev opencode-pod-<project> opencode run \
     "Run /gsd-autonomous using design at /workspace/docs/planning/design-doc.md. \
      No questions, no pauses. Ship when done."
   ```
5. `--watch`: poll `git log --oneline -5` on the workspace branch; report phase transitions. Otherwise report completion state only.
6. `--timeout`: if elapsed time exceeds the limit, `podman exec ... pkill -f gsd-autonomous` and report.
7. Cleanup: prompt then `opencode-pod stop`.
</process>

<execution_context>
The container's opencode runs the `autonomous` profile's GSD with `tdd_mode: true` and injected superpowers skills (`systematic-debugging`, `verification-before-completion`, `requesting-code-review`). Quality gates are an explicit, optional container stage gated by `quality_gates.enabled` (default false).
</execution_context>
