# AGENTS.md — opencode-pod

## Version bumps

When bumping `VERSION` for a release, also update `SCRIPT_VERSION` in `opencode-pod` to match.

## Permission fix for keep-id volumes

The `fix_home_ownership` function uses a try-verify loop (offsets 0, 1000,
1001) with a write verification via `podman exec ... test -w`. This handles
all podman versions where keep-id maps host user to different container
UIDs. Do NOT assume a single offset works universally — the mapping varies
by podman version.

When adding a new offset or changing the loop, ensure both the chown and
verification are in the same `if`/`then` pair so wrong ownership is caught
immediately.

**Probe approach (replaces try-verify loop):** The current implementation
creates a temp file via `podman unshare touch`, checks its container UID
via `podman exec -u 0 stat` (root always exists), then runs a single
`podman unshare chown` with the detected offset. This avoids the bootstrap
problem where the dev user doesn't exist yet.
