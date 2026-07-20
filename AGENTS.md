# AGENTS.md — opencode-pod

## Version bumps

When bumping `VERSION` for a release, also update `SCRIPT_VERSION` in `opencode-pod` to match.

## Permission fix for keep-id volumes

The `fix_home_ownership` function uses a **probe approach**: creates a temp
file via `podman unshare touch`, checks its container UID via `podman exec
-u 0 stat` (root always exists), then runs a single `podman unshare chown`
with the detected offset.

**Offset logic:** `probe_uid == 1000` → offset `0` (chown to host user =
container dev). All other cases (probe == 0 for old keep-id, or probe ==
host_uid ≠ 1000 for CI) → offset `1000` (chown to subuid-mapped namespace
UID = container UID 1000).

This avoids the bootstrap problem where the dev user doesn't exist yet.
Do NOT assume a single offset works universally — the mapping varies by
podman version and host UID.
