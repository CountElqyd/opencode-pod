# Fix: Home Directory Ownership via `podman unshare`

**Date:** 2026-07-02
**Status:** Approved, pending implementation

## Problem

Every container ever bootstrapped by opencode-pod ends up with `/home/dev`
(and everything under it) owned by container-root instead of the `dev`
user. When `opencode` runs as `dev` (via `container_start`/`container_shell`,
which both use `podman exec -u dev`), it fails immediately:

```
EACCES: permission denied, mkdir '/home/dev/.local/share/opencode/repos'
```

### Root cause (empirically confirmed)

`container_create()` passes `--cap-drop=ALL` with no `--cap-add` back
(`lib/podman.sh:277`, `lib/security.sh:7`). Confirmed via
`podman inspect --format '{{.EffectiveCaps}}'` → `[]`. Zero capabilities,
including `CAP_CHOWN`.

Every `chown` that runs *inside* the container therefore fails silently
with `EPERM`, masked everywhere by `2>/dev/null || true`:

- `adduser -D -u 1000 dev` internally tries to chown `/home/dev` to the new
  user and fails (visible in bootstrap output as
  `adduser: /home/dev: Operation not permitted`), but busybox's `adduser`
  doesn't treat this as fatal — it still writes `/etc/passwd`/`/etc/group`
  and returns 0, so the bootstrap step is marked done anyway.
- The config-copy step's `chown -R dev:dev /home/dev/.local` fails the
  same way, silently.
- The final catch-all `chown -R 1000:1000 /home/dev` at the end of
  `run_bootstrap` (added by commit `dbd1747`, the most recent of three
  prior chown-placement attempts — `d8e5d0b`, `6de645e`, `dbd1747` —
  plus two adjacent workarounds in the same commit chain: `720af6e`
  cleared UID 1000 collisions before `adduser`, `8682ad5` moved the npm
  global install to run as root) fails the same way.

Verified directly on a live container: every file under `/home/dev` —
`.bootstrap-progress`, `.ssh/*`, `.local`, `.local/share/opencode` — is
owned by `0:0`, not `1000:1000`. No chown has ever succeeded.

### Why three prior chown-placement fixes all failed

Each prior commit added another `chown` call in a different place in the
bootstrap sequence, but all of them ran *inside* the container process,
which has never had `CAP_CHOWN` since `--cap-drop=ALL` was introduced. The
capability restriction was never the thing being fixed. Notably, **none
of these attempts were caught by tests** — `grep -rn chown bats/` matches
zero lines in the entire suite. This isn't a case of mocked tests passing
and missing the bug; there was simply never any test coverage for this
behavior at all, which is why it shipped broken five times in a row
without a single test failure.

## Fix

Perform the ownership fix from the **host side** using `podman unshare`,
which is not subject to the container's capability set at all — this is
Podman's documented mechanism for fixing rootless volume ownership.

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

### Critical correctness detail: `0:0`, not `1000:1000`

This was verified empirically, not assumed, because it's easy to get
backwards:

```
podman unshare uid_map:   ns UID 0  -> host UID 1000 (the real invoking user)
                          ns UID 1+ -> host UID 100000+ (subordinate range)

container uid_map (keep-id): container UID 1000 (dev)  -> host UID 1000
                              container UID 0    (root) -> host UID 100000+
```

`podman unshare` always uses the *default* rootless mapping (host UID ->
namespace UID 0), regardless of what mapping a specific container run
uses. `--userns=keep-id` is a separate, different mapping applied only to
the container itself (self-map: host UID 1000 <-> container UID 1000).

Chaining the two mappings: `podman unshare chown 0:0` writes host UID 1000
-> which `--userns=keep-id` maps to container UID 1000 (`dev`). Using
`1000:1000` instead would write to a *subordinate* host UID (~100999),
which does not correspond to `dev` inside the container at all.

Verified end-to-end on the live container by comparing
`podman exec ... ls -lan /home/dev` (shows owner `0 0`) against
`podman unshare ls -lan <mountpoint>` (shows the same files as owner `1 1`,
i.e. unshare-namespace UID 1 = host UID 100000 = container UID 0) — the
chain matches the model exactly.

### No capability changes

`--cap-drop=ALL` is untouched. This fix requires zero capabilities inside
the container, so the "six-layer security model" claim in README.md /
DESIGN.md remains accurate without needing amendment.

## Changes

### `lib/podman.sh`

1. Add `fix_home_ownership()` (shown above), defined near the other
   bootstrap helpers, above `run_bootstrap()`.
2. In `run_bootstrap()`, replace the final line:
   ```bash
   podman exec "$CONTAINER_NAME" sh -c "chown -R 1000:1000 /home/dev" 2>/dev/null || true
   ```
   with:
   ```bash
   if ! fix_home_ownership; then
     completed_all=false
   fi
   ```
   Runs unconditionally every time `run_bootstrap` executes (matches
   current behavior — cheap, idempotent, self-healing if anything ever
   creates root-owned files later). Failure now blocks bootstrap
   completion like other critical steps, instead of being swallowed.
3. In the `opencode_config_copied` step: swap order so `mkdir -p` runs
   before `podman cp` (currently reversed, so the copy silently fails on
   every fresh container since the target directory doesn't exist yet at
   copy time). Drop the now-redundant inline
   `chown -R dev:dev /home/dev/.local` — the file it copies gets swept up
   by `fix_home_ownership` at the end of bootstrap, same as SSH keys are
   today. Replace `2>/dev/null || true` with visible warnings so future
   failures aren't invisible again.
4. In `container_start()`, the `CONTAINER_STATE == "running"` reattach
   path currently never calls `run_bootstrap` again — it only reattaches.
   Add a call to `fix_home_ownership` (not full `run_bootstrap`) before
   the exec, so containers created before this fix get remediated on the
   next plain `opencode-pod start`, without requiring a stop/start cycle
   or destroy/recreate.

### No changes to `lib/security.sh` or `container_create()`

Capabilities, `--userns=keep-id`, and all other hardening flags are
untouched.

## Testing

Two layers, because the class of bug here (wrong capability assumption,
wrong UID-mapping math) is exactly what mocked unit tests alone tend not
to catch. The prior fix attempts had no test coverage for this behavior
at all (zero matches for `chown` anywhere in `bats/`), which is how it
shipped broken five times in a row without a single failing test.

### Unit test (`bats/podman.bats`, mocked podman — matches existing convention)

Assert `run_bootstrap` calls `podman volume inspect "$HOME_VOLUME" --format ...`
and `podman unshare chown -R 0:0 <mountpoint>` (using the mocked
mountpoint value). Assert a warning is printed and `completed_all` becomes
false when `podman unshare` fails.

### Integration test (new `bats/integration.bats`, real podman)

DESIGN.md's Testing Strategy section already documents this category
("Integration tests with real Podman, marked `@slow`, skipped in CI
without Podman") but it was never implemented — all 5 existing bats files
mock `podman()` entirely. This is the first real test in that category.

- `setup()` skips (via `bats` `skip`) if `podman` isn't installed or
  `podman info` fails, so CI without podman/subuid stays green.
- Creates a real throwaway container + named volume with a unique test
  name (`opencode-pod-bats-test-$$`), runs actual bootstrap.
- Asserts `podman exec -u dev "$CONTAINER_NAME" stat -c %u ~/.local/share/opencode`
  returns `1000`.
- Asserts `podman exec -u dev "$CONTAINER_NAME" sh -c 'mkdir -p ~/.local/share/opencode/repos'`
  exits 0 — this is a direct repro of the originally reported bug.
- `teardown()` always removes the test container and volume, even on
  assertion failure.

## Out of scope

- Redesigning how opencode's npm global install is provisioned (currently
  runs as root; left as-is).
- Any change to `--cap-drop=ALL`, `--userns=keep-id`, or other
  `container_create()` hardening flags.
- Retroactively fixing containers that predate this change beyond the
  `container_start` reattach remediation described above.
