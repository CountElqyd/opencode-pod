# Session State

## Plan: Declarative toml requirements (docs/plans/2026-08-11-toml-requirements.md)

**Status:** COMPLETE — all 7 tasks implemented, all 33 steps checked in plan.md, full suite 200/200 bats passing. Branch: `feat/add-autonomous-profile`.

### Deliverables (commits 5ddec17..0a02646)

- `_declared_toml_requirements`, `_validate_toml_requirements` (Task 1)
- `_interactive`, `_toml_deltas` (Task 2)
- `_toml_set` bounded line patcher (Task 3)
- `_apply_toml_requirements` orchestrator, exit-code contract 0/1/2/3 (Task 4)
- install/update rewired through the engine; hardcoded host-network blocks removed (Task 5)
- autonomous profile migrated to `toml` block, bumped 0.2.1, tarball rebuilt + sha refreshed (Task 6)
- AGENTS.md "Profile metadata releases" section (Task 7)

### Intentional deviations from the plan (all verified by spec + quality reviews)

1. **Task 2 degrade assertion** — plan test asserted single-tab `network\tmode\thost` for the unparsable case; correct output is double-tab `network\tmode\t\thost` (empty current column). Single-tab would break Task 4's `read -r section key curval newval` parser.
2. **Task 2 tomllib-unavailable degradation** — plan's `import tomllib` was outside the try/except; moved inside so Python <3.11 degrades cleanly (exit 0, all-differ) per plan line 12.
3. **Task 2 `norm()`** — `_toml_deltas` normalizes current values (int/bool → string, True→"true") so type mismatches don't produce spurious deltas; also survives top-level scalar section collisions.
4. **Task 3 patcher rewrite** — plan's `BASH_REMATCH` + append-at-EOF broke in zsh and wrote keys outside their section when the target section wasn't last. Rewrote with pending-flag section-boundary logic, hoisted regexes (zsh `=~` strips unquoted escapes), substring header extraction. `pending` must be cleared on in-place rewrite (duplicate-key regression found in re-review).
5. **Task 3 hardening** — regex-escaped keys (env keys like `A.B`), permissive section-header pattern (trailing whitespace/comments), value escaping for `"`/`\`, symlink resolution + `chmod --reference` + same-dir `mktemp`, guarded RETURN trap.
6. **Task 4 security** — `_declared_toml_requirements` call gets `|| return 1` (prevents fail-open: malformed metadata → empty stdout + rc 1 was being treated as "no requirements").
7. **Task 4 prompt var** — plan read lowercase `response` but bats override sets `RESPONSE`; implementation uses uppercase `RESPONSE` (tests are the executable spec).
8. **Task 4 `builtin read`** — exported `read()` override in tests shadows the builtin; delta loops and `_toml_set` use `builtin read` so they terminate. Works in bash and zsh.
9. **Task 4 wire format** — delta wire format is `\x1f` (unit separator), NOT tab: `IFS=$'\t'` collapses empty middle fields (lost declared value on absent keys). All `_toml_deltas` tests assert `\x1f` output.
10. **Task 4 control chars** — `_validate_toml_requirements` rejects control characters in values AND env keys (security: network-fetched metadata drives host writes).
11. **Task 5 config refresh** — after applying deltas, `_apply_toml_requirements` re-runs `parse_toml` (guarded by `declare -f`) before `container_setup` so the recreated container uses the NEW network mode, not stale `CONFIG_NETWORK_MODE`.
12. **Task 5 install rc handling** — install treats rc=0 AND rc=2 (applied+recreated) as success; only rc=1 (hard error) and rc=3 (declined) abort. The plan's `|| { exit 1 }` form incorrectly aborted on rc=2.
13. **Task 5 update recreate** — a recreate (rc=2) bypasses the "already at" shortcut and reinstalls the profile + re-saves registry, because `container_destroy` deletes the registry and home volume. `apply_rc -ne 2` guard on the version gate.
14. **Task 5 set -euo pipefail safety** — `_toml_set` ends with `trap - RETURN` (RETURN trap re-fires on caller return with `$tmp` out of scope → `set -u` abort); install's apply call uses `|| apply_rc=$?` so rc=2 doesn't kill the shell under `set -e`.
15. **C1 (whole-branch review)** — `run_bootstrap` in lib/podman.sh:233 armed `trap "rmdir ... " RETURN` with no `|| true`; the trap re-fires on the caller's return and rmdir's non-zero exit aborts the CLI under `set -e` — killing the recreate flow (container destroyed, left stopped, profile/registry never reinstalled). Fixed with `rmdir ... || true`.
16. **I1 (whole-branch review)** — declared `env` keys were validated only for control chars; keys like `A.B`, `FOO"`, `FOO]` passed and, once written by `_toml_set`, broke the tool's own `parse_toml` reader (bricking every opencode-pod command). Validation now restricts env keys to `[A-Za-z_][A-Za-z0-9_]*` (bare identifiers, matching what parse_toml accepts).
17. **I2 (whole-branch review)** — the config-refresh re-parse after `_toml_set` could serve a stale mtime-cached value for same-second writes. `parse_toml` gained a `force` arg (second positional) to bypass the cache; `_apply_toml_requirements` calls `parse_toml "opencode-pod.toml" force`.

### Verified behaviors

- Full suite `bats bats/` = 202/202 passing (plan expected 147/148; the anticipated `bats/podman.bats` test-48 WIP failure does NOT exist at this commit).
- Production-style simulation (`set -euo pipefail` + sourced lib) for install/update apply/recreate/decline/non-TTY/no-delta paths — all exit codes correct.
- zsh + bash parity verified for all new helpers.

### Not committed

- Untracked `debug` file in repo root (851KB, pre-existing). Do NOT sweep into commits. Review whether to gitignore or remove.
- No state.md existed before; this file created as the plan-status record.

### Docs

- README.md + profiles/README.md updated to document the toml requirements feature (commit 8031e6d on feat/add-autonomous-profile):
  - README.md Profiles section: paragraph on the `toml` block, diff/prompt/recreate flow, decline semantics, update version-gate independence, non-TTY behavior.
  - profiles/README.md: `profile.json` table row updated; new "Declaring toml requirements" section with JSON example, v1 allowlist table, legacy `network` alias (toml wins), recreate/destructive warning.
  - Verified semantics against lib/profiles.sh (allowlist keys, rc 3 decline on install aborts / update warns, rc 1 non-TTY install aborts / update warns, rc 2 recreate).
