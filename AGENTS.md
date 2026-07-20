# AGENTS.md — opencode-pod

## Version bumps

When bumping `VERSION` for a release, also update `SCRIPT_VERSION` in `opencode-pod` to match.

## Permission fix for keep-id volumes

The `fix_home_ownership` function uses a **probe + verify loop**: creates a
temp file via `podman unshare touch`, checks its container UID via
`podman exec -u 0 stat` (root always exists), then tries offsets in
probe-guided order and verifies each by checking a verify file's container
UID. The probe alone can't detect subuid off-by-one (podman 6.0.1), so
verification is required.

**Offset logic:** `probe_uid == 1000` → try `[0, 1000, 1001]`.
`probe == 0` → try `[1000, 1001, 0]`. Else → try `[1000, 0, 1001]`.
First offset that makes verify file appear as container UID 1000 wins.
Subsequent calls try the same offset first (idempotent).

This avoids the bootstrap problem where the dev user doesn't exist yet.
Do NOT assume a single offset works universally — the mapping varies by
podman version and host UID.
