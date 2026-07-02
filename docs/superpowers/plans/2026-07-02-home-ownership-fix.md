# Home Directory Ownership Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `/home/dev` ownership so the `dev` user can actually write to its own home directory after bootstrap (currently blocked by `EACCES`), by replacing five failed in-container `chown` attempts with one correct host-side fix, without weakening any existing security hardening.

**Architecture:** A new `fix_home_ownership()` function in `lib/podman.sh` performs the ownership fix via `podman unshare chown -R 0:0 <volume-mountpoint>` — run on the host, outside the container's (intentionally empty) capability set. It's called at the end of `run_bootstrap()` (replacing the broken final chown) and from `container_start()`'s reattach path (remediates the already-running container from before this fix). The `opencode_config_copied` step's `mkdir`/`cp` order gets corrected. Two test layers: existing-convention mocked bats unit tests (fast, verify command construction) plus a new real-podman integration suite (verifies actual filesystem/UID behavior — the only thing that could have caught this bug, since it was never covered by any test in five prior attempts).

**Tech Stack:** Bash (`set -euo pipefail`), Podman 5.x rootless (`--userns=keep-id`, `--cap-drop=ALL`), bats-core 1.13.0 (local npm devDependency at `node_modules/.bin/bats`).

**Design doc:** `docs/superpowers/specs/2026-07-02-home-ownership-fix-design.md`

**Baseline verified:** `./node_modules/.bin/bats bats/` → 65 tests, 0 failures, before any change in this plan.

---

### Task 1: Add `fix_home_ownership()` function

**Files:**
- Modify: `lib/podman.sh:172-174` (insert new function between `mark_bootstrap_step` and `run_bootstrap`)
- Test: `bats/podman.bats` (append new tests at end of file)

- [ ] **Step 1: Write the failing tests**

Append to `bats/podman.bats`:

```bash

# --- fix_home_ownership ---

@test "fix_home_ownership resolves mountpoint and chowns via podman unshare" {
  source lib/podman.sh
  HOME_VOLUME="test-home-volume"

  podman() {
    case "$1" in
      volume)
        if [[ "$2" == "inspect" ]]; then
          printf '%s\n' "/fake/mountpoint/path"
          return 0
        fi
        ;;
      unshare)
        printf '%s\n' "$*" > "$TESTDIR/unshare_args"
        return 0
        ;;
    esac
    return 0
  }
  export -f podman

  run fix_home_ownership
  [ "$status" -eq 0 ]

  local cmd
  cmd="$(cat "$TESTDIR/unshare_args")"
  [[ "$cmd" == *"chown -R 0:0"* ]]
  [[ "$cmd" == *"/fake/mountpoint/path"* ]]
}

@test "fix_home_ownership warns and fails when volume inspect fails" {
  source lib/podman.sh
  HOME_VOLUME="test-home-volume"

  podman() {
    case "$1" in
      volume) return 1 ;;
    esac
    return 0
  }
  export -f podman

  run fix_home_ownership
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARNING"* ]]
}

@test "fix_home_ownership warns and fails when podman unshare chown fails" {
  source lib/podman.sh
  HOME_VOLUME="test-home-volume"

  podman() {
    case "$1" in
      volume)
        if [[ "$2" == "inspect" ]]; then
          printf '%s\n' "/fake/mountpoint/path"
          return 0
        fi
        ;;
      unshare) return 1 ;;
    esac
    return 0
  }
  export -f podman

  run fix_home_ownership
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARNING"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: 3 new failures with `fix_home_ownership: command not found` (or similar "not found" bats error), all other 29 existing podman.bats tests still pass.

- [ ] **Step 3: Implement `fix_home_ownership()`**

In `lib/podman.sh`, insert immediately before the `run_bootstrap()` function (i.e., right after `mark_bootstrap_step`'s closing `}` at line 172, before the blank line and `run_bootstrap() {` at line 174):

```bash
fix_home_ownership() {
  local mountpoint
  mountpoint="$(podman volume inspect "$HOME_VOLUME" --format '{{.Mountpoint}}' 2>/dev/null)" || {
    printf 'WARNING: could not resolve home volume mountpoint; skipping ownership fix\n' >&2
    return 1
  }
  if ! podman unshare chown -R 0:0 "$mountpoint"; then
    printf 'WARNING: failed to fix home directory ownership (dev user may lack write access)\n' >&2
    return 1
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: all 32 tests pass (29 existing + 3 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/podman.sh bats/podman.bats
git commit -m "feat: add fix_home_ownership using podman unshare

--cap-drop=ALL strips CAP_CHOWN, so every in-container chown has always
silently failed (confirmed via podman inspect --format EffectiveCaps ->
[]). Fix runs from the host side via podman unshare, which isn't subject
to the container's capability set. Uses chown -R 0:0 (not 1000:1000) --
verified empirically that podman unshare's default namespace UID 0 maps
to the real host user, which --userns=keep-id maps to container UID 1000
(dev). See docs/superpowers/specs/2026-07-02-home-ownership-fix-design.md"
```

---

### Task 2: Wire `fix_home_ownership()` into `run_bootstrap()`

**Files:**
- Modify: `lib/podman.sh:252-255` (replace broken final chown)
- Test: `bats/podman.bats` (append new tests)

- [ ] **Step 1: Write the failing tests**

Append to `bats/podman.bats`:

```bash

@test "run_bootstrap calls fix_home_ownership at the end" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() {
    case "$1" in
      start) return 0 ;;
      exec) return 0 ;;
      cp) return 0 ;;
      volume)
        if [[ "$2" == "inspect" ]]; then
          printf '%s\n' "$TESTDIR/fake-mount"
          return 0
        fi
        ;;
      unshare)
        printf '%s\n' "$*" >> "$TESTDIR/unshare_calls"
        return 0
        ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]

  local cmd
  cmd="$(cat "$TESTDIR/unshare_calls")"
  [[ "$cmd" == *"chown -R 0:0"* ]]
  [[ "$cmd" == *"$TESTDIR/fake-mount"* ]]
}

@test "run_bootstrap reports incomplete when fix_home_ownership fails" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() {
    case "$1" in
      start) return 0 ;;
      exec) return 0 ;;
      cp) return 0 ;;
      volume) return 1 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"WARNING: could not resolve home volume mountpoint"* ]]
  [[ "$output" == *"Bootstrap incomplete"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: 2 new failures — the first because `run_bootstrap` still calls the old broken inline chown (never writes `unshare_calls`), the second because `run_bootstrap` currently always reports "Bootstrap complete" regardless of the old chown's outcome (it's swallowed by `|| true` and doesn't affect `completed_all`, and the old code never prints any "WARNING" text at all).

- [ ] **Step 3: Replace the broken final chown**

In `lib/podman.sh`, find this block inside `run_bootstrap()` (currently around line 252-255):

```bash
  # Fix home dir ownership — all root-run steps (ssh_keygen, config_copy, npm -g)
  # create root-owned files inside /home/dev. chown after ALL steps so dev can
  # write to ~/.ssh, ~/.local, ~/.npm, ~/.cache at runtime.
  podman exec "$CONTAINER_NAME" sh -c "chown -R 1000:1000 /home/dev" 2>/dev/null || true
```

Replace with:

```bash
  # Fix home dir ownership — all root-run steps (ssh_keygen, config_copy, npm -g)
  # create root-owned files inside /home/dev. --cap-drop=ALL strips CAP_CHOWN,
  # so this must run from the host side via podman unshare, not inside the
  # container. Runs after ALL steps so dev can write to ~/.ssh, ~/.local,
  # ~/.npm, ~/.cache at runtime.
  if ! fix_home_ownership; then
    completed_all=false
  fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: all 34 tests pass (32 from Task 1 + 2 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/podman.sh bats/podman.bats
git commit -m "fix: wire fix_home_ownership into run_bootstrap, replacing broken chown

Replaces the final in-container chown (which has never worked due to
--cap-drop=ALL) with the host-side fix_home_ownership call. Failure now
blocks bootstrap completion like other critical steps instead of being
silently swallowed by '|| true'."
```

---

### Task 3: Fix `opencode_config_copied` ordering bug

**Files:**
- Modify: `lib/podman.sh:229-237`
- Test: `bats/podman.bats` (append new tests)

- [ ] **Step 1: Write the failing tests**

Append to `bats/podman.bats`:

```bash

@test "opencode_config_copied creates directory before copying (podman cp fails on missing target dir)" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  export OPCODE_POD_LIB_DIR="$TESTDIR/lib-dir"
  mkdir -p "$OPCODE_POD_LIB_DIR" "$TESTDIR/example"
  printf '{}' > "$TESTDIR/example/opencode.json"

  podman() {
    case "$1" in
      start) return 0 ;;
      volume)
        [[ "$2" == "inspect" ]] && printf '%s\n' "$TESTDIR/fake-mount"
        return 0
        ;;
      unshare) return 0 ;;
      exec)
        if [[ "$*" == *"mkdir -p /home/dev/.local/share/opencode"* ]]; then
          touch "$TESTDIR/mkdir-ran"
        fi
        return 0
        ;;
      cp)
        if [[ "$*" == *"opencode.json"* ]]; then
          # Simulates podman cp's real behavior: fails if the target
          # directory doesn't exist inside the container yet.
          [[ -f "$TESTDIR/mkdir-ran" ]] || return 1
        fi
        return 0
        ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"*"opencode config"* ]]
}

@test "opencode_config_copied warns visibly when copy fails" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  export OPCODE_POD_LIB_DIR="$TESTDIR/lib-dir"
  mkdir -p "$OPCODE_POD_LIB_DIR" "$TESTDIR/example"
  printf '{}' > "$TESTDIR/example/opencode.json"

  podman() {
    case "$1" in
      start) return 0 ;;
      volume)
        [[ "$2" == "inspect" ]] && printf '%s\n' "$TESTDIR/fake-mount"
        return 0
        ;;
      unshare) return 0 ;;
      exec) return 0 ;;
      cp)
        if [[ "$*" == *"opencode.json"* ]]; then
          return 1
        fi
        return 0
        ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [[ "$output" == *"WARNING"*"opencode config"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: first new test fails (current code calls `podman cp` before `mkdir`, so the mocked `cp` returns 1 since `mkdir-ran` doesn't exist yet, but the current code has `2>/dev/null || true` swallowing that — meaning the *warning* the test checks for never actually appears anyway since there's no warning text in current code at all, so both tests actually fail on the `[[ "$output" == *"WARNING"* ]]`-style assertions since no "WARNING" text exists yet in this step's current implementation).

- [ ] **Step 3: Fix the ordering and add visible warnings**

In `lib/podman.sh`, find this block inside `run_bootstrap()` (currently around line 229-237):

```bash
  if ! is_bootstrap_step_done "$progress" "opencode_config_copied"; then
    printf '%s\n' "Copying OpenCode config..."
    local example_config="${OPCODE_POD_LIB_DIR:-$HOME/.local/share/opencode-pod}/../example/opencode.json"
    if [[ -f "$example_config" ]]; then
      podman cp "$example_config" "$CONTAINER_NAME:/home/dev/.local/share/opencode/opencode.json" 2>/dev/null || true
      podman exec "$CONTAINER_NAME" sh -c "mkdir -p /home/dev/.local/share/opencode && chown -R dev:dev /home/dev/.local" 2>/dev/null || true
    fi
    mark_bootstrap_step "$progress" "opencode_config_copied"
  fi
```

Replace with:

```bash
  if ! is_bootstrap_step_done "$progress" "opencode_config_copied"; then
    printf '%s\n' "Copying OpenCode config..."
    local example_config="${OPCODE_POD_LIB_DIR:-$HOME/.local/share/opencode-pod}/../example/opencode.json"
    if [[ -f "$example_config" ]]; then
      if ! podman exec "$CONTAINER_NAME" sh -c "mkdir -p /home/dev/.local/share/opencode"; then
        printf 'WARNING: failed to create opencode config directory\n' >&2
      elif ! podman cp "$example_config" "$CONTAINER_NAME:/home/dev/.local/share/opencode/opencode.json"; then
        printf 'WARNING: failed to copy opencode config\n' >&2
      fi
    fi
    mark_bootstrap_step "$progress" "opencode_config_copied"
  fi
```

Note: the inline `chown -R dev:dev /home/dev/.local` is removed entirely — it never worked (same `CAP_CHOWN` restriction as everything else), and this file now gets swept up by `fix_home_ownership` at the end of bootstrap, same as SSH keys already are.

- [ ] **Step 4: Run tests to verify they pass**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: all 36 tests pass (34 from Task 2 + 2 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/podman.sh bats/podman.bats
git commit -m "fix: create opencode config directory before copying into it

podman cp ran before mkdir -p created the target directory, so the copy
silently failed on every fresh container (masked by 2>/dev/null || true).
Swapped the order and replaced silent swallowing with visible warnings.
Dropped the inline chown -R dev:dev, which never worked for the same
CAP_CHOWN reason as everything else — fix_home_ownership sweeps this file
up at the end of bootstrap instead."
```

---

### Task 4: Remediate already-running containers on reattach

**Files:**
- Modify: `lib/podman.sh:356-359`
- Test: `bats/podman.bats` (append new test)

- [ ] **Step 1: Write the failing test**

Append to `bats/podman.bats`:

```bash

@test "container_start calls fix_home_ownership when reattaching to running container" {
  source lib/podman.sh
  CONTAINER_NAME="test"
  HOME_VOLUME="test-home"
  CONTAINER_STATE="running"

  podman() {
    case "$1" in
      volume)
        [[ "$2" == "inspect" ]] && printf '%s\n' "$TESTDIR/fake-mount"
        return 0
        ;;
      unshare)
        printf '%s\n' "$*" > "$TESTDIR/unshare_args"
        return 0
        ;;
      exec) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run container_start
  [ "$status" -eq 0 ]

  local cmd
  cmd="$(cat "$TESTDIR/unshare_args")"
  [[ "$cmd" == *"chown -R 0:0"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: 1 new failure — `container_start`'s "running" branch currently only reattaches, never calls `fix_home_ownership`, so `$TESTDIR/unshare_args` is never created and `cat` fails.

- [ ] **Step 3: Add the remediation call**

In `lib/podman.sh`, find this block (currently around line 356-359):

```bash
container_start() {
  if [[ "$CONTAINER_STATE" == "running" ]]; then
    printf '%s\n' "Reattaching to running container: $CONTAINER_NAME"
    podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /bin/sh
    return 0
  fi
```

Replace with:

```bash
container_start() {
  if [[ "$CONTAINER_STATE" == "running" ]]; then
    printf '%s\n' "Reattaching to running container: $CONTAINER_NAME"
    fix_home_ownership || true
    podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /bin/sh
    return 0
  fi
```

Note: `|| true` here is intentional and different from Task 2's handling — on reattach we want the user to still get a shell even if remediation hits an edge case; the warning still prints via `fix_home_ownership`'s own `stderr` output either way.

- [ ] **Step 4: Run test to verify it passes**

Run: `./node_modules/.bin/bats bats/podman.bats`
Expected: all 37 tests pass (36 from Task 3 + 1 new), 0 failures. Specifically re-verify the two pre-existing tests that also exercise this branch still pass: `container_start reattaches to running container after setup` and `container_start execs as dev user`.

- [ ] **Step 5: Commit**

```bash
git add lib/podman.sh bats/podman.bats
git commit -m "fix: remediate stale root-owned files on container_start reattach

container_start's running-container branch never called run_bootstrap
again, so containers created before this fix would stay broken forever
even after upgrading opencode-pod. Adding fix_home_ownership here means a
plain 'opencode-pod start' repairs an already-running container without
needing a stop/start cycle or destroy/recreate."
```

---

### Task 5: Add real-podman integration test suite

**Files:**
- Create: `bats/integration.bats`

- [ ] **Step 1: Write the integration test file**

Create `bats/integration.bats`:

```bash
#!/usr/bin/env bats
# Integration tests using a real podman daemon (not mocked). These create
# real throwaway containers and volumes via the actual container_create/
# run_bootstrap/fix_home_ownership functions (not hand-duplicated podman
# flags), so they stay in sync with the real implementation. Skipped
# automatically if podman isn't installed or isn't usable (e.g. CI runners
# without rootless subuid/subgid configured) — matches DESIGN.md's
# documented "@slow, skipped in CI without Podman" integration strategy.
#
# These are slow (real apk + npm installs, real container lifecycle) and
# require network access. Run explicitly, not as part of the fast unit
# suite: ./node_modules/.bin/bats bats/integration.bats

setup() {
  if ! command -v podman >/dev/null 2>&1; then
    skip "podman not installed"
  fi
  if ! podman info >/dev/null 2>&1; then
    skip "podman not usable in this environment"
  fi

  source lib/toml.sh
  source lib/podman.sh
  source lib/security.sh

  WORKDIR="$(mktemp -d)"
  mkdir -p "$WORKDIR/project"
  cat > "$WORKDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
packages = ["git"]
EOF

  resolve_project "$WORKDIR/project"
  podman volume create "$HOME_VOLUME" >/dev/null
  ( cd "$WORKDIR/project" && container_create >/dev/null )
  podman start "$CONTAINER_NAME" >/dev/null
}

teardown() {
  if [[ -n "${CONTAINER_NAME:-}" ]]; then
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman volume rm "$HOME_VOLUME" >/dev/null 2>&1 || true
  fi
  [[ -n "${WORKDIR:-}" ]] && rm -rf "$WORKDIR"
}

@test "[integration] dev user owns home directory after bootstrap" {
  run_bootstrap

  run podman exec -u dev "$CONTAINER_NAME" sh -c 'stat -c %u /home/dev/.local/share/opencode'
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}

@test "[integration] dev user can create opencode data directories without EACCES" {
  run_bootstrap

  run podman exec -u dev "$CONTAINER_NAME" sh -c 'mkdir -p /home/dev/.local/share/opencode/repos && touch /home/dev/.local/share/opencode/repos/test-file'
  [ "$status" -eq 0 ]
}

@test "[integration] fix_home_ownership remediates stale root-owned files from before this fix" {
  # Simulate a pre-fix container: a root-owned file created without ever
  # running bootstrap (no dev user, no ownership fix ever applied).
  podman exec "$CONTAINER_NAME" sh -c 'mkdir -p /home/dev/.local/share/opencode && touch /home/dev/.local/share/opencode/stale-root-file'

  run fix_home_ownership
  [ "$status" -eq 0 ]

  run podman exec "$CONTAINER_NAME" sh -c 'stat -c %u /home/dev/.local/share/opencode/stale-root-file'
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}
```

- [ ] **Step 2: Run the integration tests**

Run: `./node_modules/.bin/bats bats/integration.bats`
Expected: 3 tests pass. This will take real time (each test pulls/uses the Wolfi image, runs `apk add`, and the first two run a real `npm install -g opencode-ai` — expect low single-digit minutes total, not seconds). Requires network access.

If any test fails, debug against a real container before proceeding — do not weaken the assertions to make them pass. This suite exists specifically to catch what the mocked tests structurally cannot.

- [ ] **Step 3: Commit**

```bash
git add bats/integration.bats
git commit -m "test: add real-podman integration suite for home ownership fix

First implementation of the integration test category DESIGN.md's Testing
Strategy already documented but never built. Directly reproduces the
originally reported bug (mkdir ~/.local/share/opencode/repos -> EACCES)
against a real container, and verifies fix_home_ownership remediates a
simulated pre-fix container with stale root-owned files."
```

---

### Task 6: Update DESIGN.md documentation

**Files:**
- Modify: `DESIGN.md:54-59` (file tree)
- Modify: `DESIGN.md:391-405` (Testing Strategy section)

- [ ] **Step 1: Add integration.bats to the file tree**

In `DESIGN.md`, find:

```
├── bats/
│   ├── toml.bats               # TOML parser + caching tests
│   ├── distro.bats             # distro detection tests
│   ├── podman.bats             # container lifecycle, setup, error classification, bootstrap tests
│   ├── security.bats           # hardening flag verification
│   └── install.bats            # installer file placement tests
```

Replace with:

```
├── bats/
│   ├── toml.bats               # TOML parser + caching tests
│   ├── distro.bats             # distro detection tests
│   ├── podman.bats             # container lifecycle, setup, error classification, bootstrap tests
│   ├── security.bats           # hardening flag verification
│   ├── install.bats            # installer file placement tests
│   └── integration.bats        # real-podman tests (@slow, skipped without podman)
```

- [ ] **Step 2: Mark the integration test category as implemented**

In `DESIGN.md`, find:

```
- **Integration tests** with real Podman (marked `@slow` in bats, skipped in CI without Podman):
  - Create container from Wolfi base, verify it starts
  - Install packages via `apk add -U`, verify via `apk info -e`
  - Setup/start/stop/destroy lifecycle
  - Bootstrap checkpoint resume
```

Replace with:

```
- **Integration tests** (`bats/integration.bats`) with real Podman, skipped automatically in CI or any environment without a usable `podman`:
  - Dev user owns `/home/dev` after bootstrap (direct regression test for
    the `--cap-drop=ALL` / `CAP_CHOWN` ownership bug)
  - Dev user can create OpenCode data directories without `EACCES`
  - `fix_home_ownership` remediates a simulated pre-fix container with
    stale root-owned files
```

- [ ] **Step 3: Commit**

```bash
git add DESIGN.md
git commit -m "docs: reflect implemented integration test suite in DESIGN.md"
```

---

### Task 7: Full verification sweep

**Files:** none (verification only)

- [ ] **Step 1: Run shellcheck**

Run: `shellcheck opencode-pod install.sh lib/*.sh`
Expected: no errors. (Matches the CI `lint` job in `.github/workflows/test.yml`.)

- [ ] **Step 2: Run the full fast unit suite**

Run: `./node_modules/.bin/bats bats/toml.bats bats/distro.bats bats/podman.bats bats/security.bats bats/install.bats`
Expected: 73 tests, 0 failures (65 baseline + 8 new unit tests from Tasks 1-4).

- [ ] **Step 3: Run the integration suite**

Run: `./node_modules/.bin/bats bats/integration.bats`
Expected: 3 tests, 0 failures.

- [ ] **Step 4: Manually verify against the user's actual pre-existing broken container**

Run:
```bash
source lib/toml.sh && source lib/podman.sh && source lib/security.sh
resolve_project ~/dev/personal_blog
fix_home_ownership
podman exec -u dev "$CONTAINER_NAME" sh -c 'mkdir -p ~/.local/share/opencode/repos && echo OK'
```
Expected: prints `OK` with no `EACCES` error — this is the exact repro from the original bug report, now fixed on the container that's been broken since it was first created.

- [ ] **Step 5: Final commit if any fixups were needed**

If Steps 1-4 required any adjustments, commit them:
```bash
git add -A
git commit -m "fix: address issues found during verification sweep"
```
(Skip this step if no fixups were needed — the six prior commits already stand on their own.)
