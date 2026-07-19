# Profile Install via Container Exec

## Problem

`opencode-pod profile install <name>` downloads a tarball and `setup.sh` to
`./profiles/<name>/` on the **host**, then tells the user to run
`bash profiles/<name>/setup.sh` **inside** the container. This risks the user
accidentally running the setup script on the host machine, which would install
OpenCode config/skills/agents into the host's `~/.config/opencode` instead of the
container's isolated environment.

## Design

`profile install` no longer writes anything to the host workspace. Instead it
streams the tarball and setup script directly inside the container via
`podman exec`, runs setup, and cleans up.

### Flow

```
opencode-pod profile install ralph
  │
  ├─ 1. Fetch index, validate profile name (unchanged)
  ├─ 2. Check registry for existing install → error unless --force
  ├─ 3. resolve_project() → check container exists
  │     └─ nonexistent? → fail: "Run 'opencode-pod setup' first."
  ├─ 4. Container stopped? → container_start() from podman.sh
  ├─ 5. podman exec -u dev <container> sh -c "
  │       TMP=/tmp/.opencode-profile-<name>
  │       mkdir -p $TMP && cd $TMP
  │       curl -sS --fail -O <tarball_url> -O <setup_url>
  │       chmod +x setup.sh && bash setup.sh
  │       rc=$?; rm -rf $TMP; exit $rc
  │     "
  ├─ 6. Non-zero exit? → print error, don't mark installed
  └─ 7. Update registry with installed version
```

### Profile update

`profile update` follows the same pattern — same `podman exec` call, no local
file download. Version diff check is still done against the index before
invoking the container exec.

### Registry

The `path` field in installed entries becomes `""` (no local files). The
registry still tracks `name`, `version`, `description`, and `installed_at` for
`profile list` and `profile info`.

### Required changes

| File | Change |
|------|--------|
| `lib/profiles.sh` | Source `lib/podman.sh`. Rework `cmd_profile_install` and `cmd_profile_update` to exec setup.sh inside container instead of downloading to host. |
| `bats/profiles.bats` | Rewrite `cmd_profile_install` and `cmd_profile_update` tests to mock `resolve_project`, `CONTAINER_NAME`, and `podman exec` behavior. |

### Dependencies

- `lib/profiles.sh` sources `lib/podman.sh` for `resolve_project()` and
  `container_start()`. This is safe because `opencode-pod` always sources both
  libraries already — this just makes the dependency explicit.
- Container must have `curl` (wolfi-base has it). If absent, setup.sh will fail
  with a clear curl error.

### Edge cases

| Case | Behavior |
|------|----------|
| Container doesn't exist | Fail: "Run 'opencode-pod setup' first." |
| Container stopped | Auto-start before exec |
| curl fails inside container | Error bubbles up; temp dir cleaned |
| setup.sh fails | Error printed; registry not updated |
| `--force` | Re-execs setup.sh regardless of registry state |
| Network mode prompt | Still prompts about host networking (before exec) |

### What stays the same

- `profile list` and `profile info` (registry check unchanged)
- `profile index.json` format and version tracking
- Network mode prompt logic (`host` network profiles)
- All existing setup.sh scripts (no modifications needed)
