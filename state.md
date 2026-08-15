# Session State

## Plan: Profile install permissions fix (docs/plans/2026-08-15-profile-install-permissions.md)

**Status:** COMPLETE — Tasks 1-5 implemented via subagent-driven-development (implementer + spec review + quality review per task), whole-branch reviewed (APPROVED), full suite 216/216 bats passing, shellcheck 0.11.0 clean (via npx), `validate-version.sh` exit 0. Branch: `feat/update` (local; no merge per repo pattern). Task 5 Step 4 (real-podman smoke test) is USER-RUN.

### Deliverables (commits 30c6cee..24a79fc on feat/update)

- `lib/profiles.sh` — `_container_exec_setup` rewritten: stage tarball + setup.sh into the container via `podman exec -i -u "${CONTAINER_USER:-dev}"` stdin (user-owned by construction — fixes EPERM/EACCES with `--cap-drop=ALL`/no-CAP_CHOWN); root (`-u 0`) pre-cleanup `rm -rf` self-heals stale root-owned staging dirs from pre-0.4.1; `set -e` in the run step. **0.4.2 regression fix:** the tarball is staged as a file (`cat > <name>.tar.gz`), not extracted (`tar xzf - -C`), restoring the `$SCRIPT_DIR/<name>.tar.gz` contract every setup.sh relies on.
- `bats/profiles.bats` — `cmd_profile_install success execs setup inside container` rewritten to assert the sequence (exec -u 0 cleanup, exec -i -u dev stdin staging, `cat > <name>.tar.gz`, `cat > setup.sh`, `set -e`, `rm -rf`, no `cp`, no `chmod`).
- `README.md` — profile section replaced with full "Installing a Profile" guide (prereqs, quick start, install mechanics, `opencode-pod list` vs `profile list` disambiguation, profile table ralph 0.2.3 / swarm 0.1.1 / autonomous 0.2.4, toml-requirements paragraph).
- `opencode-pod`/`VERSION`/`README.md` badge/`CHANGELOG.md` — bumped to 0.4.1. CHANGELOG 0.4.1 section includes an APPROVED extension covering unreleased commits #28 (graphify workflow), #29 (profile guides + version bumps), #30 (`list` command + destroy fix in config-less dirs).
- `known-issues.md` — updated on disk (new EPERM/EACCES symptom entry under `## Configuration`; hardcode `-u dev` entry marked fixed in 0.4.1) but deliberately NOT committed: the file is gitignored (`.gitignore:13`, added a436b56) and was never tracked. USER DECISION: keep local-only.

### Deviations from the plan (all reviewed + approved)

1. **curl mock `$3` → `$4`** (Task 1, plan test body had a latent bug): the spec's own invocation `curl -sS --fail -o PATH URL` puts the output path at `$4` (`-o` is `$3`); `touch "$3"` = `touch -o` → staged file never existed, breaking the new stdin redirect `< file`. Old code was unaffected because `podman cp` was mocked. Fix required for the specified test+implementation pair to pass.
2. **5 neighboring curl mocks extended with `touch "$4"`** (Task 1): toml-delta/update/install tests' `curl(){ touch "$TESTDIR/curl_called"; return 0; }` didn't create the staged file → new stdin redirect failed fast. Same-file, minimal, required for mandated full-suite PASS.
3. **CHANGELOG 0.4.1 extension** (Task 4): plan's verbatim CHANGELOG body omitted unreleased commits #28/#29/#30 (graphify workflow, profile guides, `list` command + destroy fix) that ship inside 0.4.1 — release notes would have been incomplete (incl. the new `list` command the README documents). USER DECISION: extend notes (added `### Features` section + third Bug Fix bullet). Version stays 0.4.1 (patch bump kept per plan + user).
4. **Task 2 commit step N/A**: `known-issues.md` is gitignored/untracked; plan assumed tracked. USER DECISION: keep local-only (see above).

### Verified

- Full suite `npx bats bats/` = 216/216 passing (exit 0).
- `npx --yes shellcheck opencode-pod lib/*.sh` = clean (exit 0, shellcheck 0.11.0).
- `bash scripts/validate-version.sh` = exit 0; diff stat = 6 tracked files (CHANGELOG.md, README.md, VERSION, bats/profiles.bats, lib/profiles.sh, opencode-pod) + known-issues.md on disk.
- Whole-branch review: APPROVED. 3 Low/informational findings, none gating: (L1) `--force re-installs` test has no curl mock → real network dependency (pre-existing, out of scope); (L2) `set -e` skips cleanup on setup.sh failure → user-owned leftover, self-heals next run (plan-mandated); (L3) root pre-cleanup swallows container-not-running error → callers guarantee started container.
- Security verified: no hardening changes (`--cap-drop=ALL`/`--userns=keep-id` intact), no capability dependency, no injection vector (profile name validated `^[a-zA-Z0-9_-]+$`, `container_tmp` fixed-format, user passed as separate argv).

### Open items

- USER: Task 5 Step 4 smoke test — on a host with podman + a stale root-owned `/tmp/.opencode-profile-*` dir, run `opencode-pod profile install --force autonomous`; expect no EPERM/EACCES, ends with installed message, staging dir gone after. **Note:** the first run of this smoke test (2026-08-15) exposed a 0.4.1 regression — see 0.4.2 fix below.
- USER: branch `feat/update` is local-only; tag/publish/release.sh are separate (not part of this plan).

## Fix: 0.4.1 staging regression — `autonomous.tar.gz not found` (0.4.2)

**Status:** COMPLETE — root cause: 0.4.1 `_container_exec_setup` staged the tarball via `tar xzf - -C` (extracted contents), but every profile's `setup.sh` requires `$SCRIPT_DIR/<name>.tar.gz` to exist and exits 1 (`Error: /tmp/.opencode-profile-<name>/<name>.tar.gz not found`). Old `podman cp` flow placed the tarball as a file; setup.sh extracted it. Staging + setup.sh were never tested together (bats mocks podman; setup.sh bats tests place the tarball beside it). Fix: stage the tarball as a file via stdin (`cat >`), preserving the 0.4.1 ownership fix. Files: lib/profiles.sh (staging), bats/profiles.bats (assertion), opencode-pod SCRIPT_VERSION + VERSION + CHANGELOG → 0.4.2.

## Plan: Profile workspace guides (docs/plans/2026-08-13-profile-guide.md)

**Status:** COMPLETE — Tasks 1-7 implemented + whole-branch reviewed (APPROVED), full suite 208/208 bats passing, determinism verified. Branch: `feat/profile-guides` (local, no merge per user choice). Task 8 smoke-test steps 3-5 are USER-RUN (podman/rm permission-blocked).

### Deliverables (commits 889b4ec..d9aac3c on feat/profile-guides)

- `profiles/{ralph,swarm,autonomous}/src/guide/PROFILE-<name>.md` — authored workspace guides (10-section skeleton, no component counts per design).
- `build.sh` (×3): pack `guide/` into each tarball. `setup.sh` (×3): guide-copy step before the idempotency guard — `[ ! -f /workspace/PROFILE-<name>.md ] || [ "$INSTALLED" != "$VERSION" ]`, non-fatal on failure, restore-on-delete.
- `profiles/index.json`: versions bumped ralph 0.2.2→0.2.3, swarm 0.1.0→0.1.1, autonomous 0.2.3→0.2.4; tarballs rebuilt; sha256 refreshed. No CLI VERSION/SCRIPT_VERSION bump.
- `.github/workflows/test.yml` + `bats/profiles.bats`: tarball guide-presence checks. `bats/profile-swarm.bats`/`profile-autonomous.bats`: version assertions updated to 0.1.1/0.2.4.
- `profiles/README.md`: Convention table row for `src/guide/`.

### Deviations from the plan (reviewed)

1. **Autonomous guide GSD-config bullet** (quality review) — plan said `~/.config/opencode/gsd-config.json` exists, but setup.sh copies gsd-config.json only to `/workspace/.planning/config.json`. Merged into one accurate `/workspace/.planning/config.json` bullet (90e544b).
2. **Version-assertion bats tests** (full-suite failure) — two pre-existing tests hardcoded pre-bump versions (swarm 0.1.0, autonomous 0.2.3); the plan didn't enumerate them. Updated (d9aac3c). Plan gap resolved inline.
3. **mktemp-under-set-e known limitation** — if `/workspace` were unwritable, `mktemp` would abort the install; `[ -d /workspace ]` is the only precondition. Out-of-contract (plan assumes writable /workspace). Documented, not fixed.

### Verified

- Full suite `bats bats/` = 208/208 passing (incl. new guide test).
- Tarball determinism: rebuild yields byte-identical tarballs (git diff empty).
- Whole-branch review: member path ↔ tarball member ↔ index sha256 consistent for all three profiles; no scope creep; no secrets/artifacts.

### Open items

- USER: Task 8 smoke test (scratch container): install profile → PROFILE-<name>.md appears; KEEP-OK (edits survive same-version reinstall); RESTORE-OK (delete + reinstall restores). Then clean up scratch container.
- USER: branch `feat/profile-guides` is local-only; merge/push when ready.

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

### v0.4.0 release prep

- CHANGELOG.md [0.4.0] entry added (2026-08-12) covering 40 commits since the 0.3.1 release base (a436b56..HEAD): autonomous profile + /autocode, declarative toml profile requirements, security hardening, bug fixes, refactor, tests, docs.
- VERSION + SCRIPT_VERSION (opencode-pod:7) + README badge bumped 0.3.1 -> 0.4.0 (were uncommitted working-tree edits; now in the release commit).
- FIXED pre-existing bug in .github/workflows/release.yml:35: awk range `/^## \[V\]/,/^## \[/` collapses to 1 line (awk treats `\[` as literal `[`, end pattern matches start line), so `head -n -2` yielded EMPTY release notes for every release. Replaced with flag-based extraction (`/^## \[V\]/ {found=1; next} found && /^## \[/ {exit} found`); verified 27-line body for 0.4.0.
- Single release commit b439777 "chore: release v0.4.0" touching CHANGELOG.md, VERSION, opencode-pod, README.md, .github/workflows/release.yml.

## Plan: Graphify skill bump to 0.9.41 (docs/plans/2026-08-13-graphify-skill-bump.md)

**Status:** COMPLETE — skill refreshed to 0.9.41 (byte-identical from upstream tag),
graphifyy pinned `==0.9.41` in setup.sh (mirrors GSD pin), regression guard added,
release bumped to v0.2.3 with rebuilt tarball + refreshed sha256.

### Key decisions

- Skill and package pinned in lockstep (Option B) — the version alarm is resolved
  permanently, not suppressed. Future graphify upgrades refresh skill + pin + mocks together.
- Task 8 smoke fully verified in scratch container: `/new-project` built 47 nodes /
  57 edges / 8 communities; plugin reminder fired; `graphify query "hello function"`
  answered from graph; `/setup-project` re-run was idempotent (incremental --update,
  no changes, hooks/AGENTS/memory all already in place).
- FM2 observed: `graphify` not on PATH in a fresh bash call (fell back to
  `python -m graphify`); documented, not fixed — hook embeds interpreter path.
- Branch kept local; no merge/push.

### Open items

- USER: remove the smoke container `opencode-pod-personal-blog-9a4783` (Exited;
  confirmed as the graphify scratch container). Workspace dir
  `/tmp/opencode/scratch-graphify` already deleted; `opencode-pod destroy` path
  no longer usable (`podman rm -f opencode-pod-personal-blog-9a4783`).
- USER: run `opencode-pod profile update autonomous` AFTER the release reaches
  remote `main` (it fetches from GitHub, not the local repo).
