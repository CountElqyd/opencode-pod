#!/usr/bin/env bats

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
packages = ["git", "openssh"]
EOF

  resolve_project "$WORKDIR/project"
  podman volume create "$HOME_VOLUME" >/dev/null
  ( cd "$WORKDIR/project" && container_create >/dev/null )
  podman start "$CONTAINER_NAME" >/dev/null
  sleep 2

  # Add dev user to system files (rootfs — works via podman exec as root)
  podman exec "$CONTAINER_NAME" sh -c "
    id dev 2>/dev/null && exit 0
    echo 'dev:x:1000:1000:dev:/home/dev:/bin/sh' >> /etc/passwd
    echo 'dev:x:1000:' >> /etc/group
  " >/dev/null 2>&1

  # Pre-create home dir skeleton on the volume using host-side podman
  # unshare (bypasses --cap-drop=ALL inside the container).
  local mountpoint
  mountpoint="$(podman volume inspect "$HOME_VOLUME" --format '{{.Mountpoint}}')"
  podman unshare mkdir -p "$mountpoint/.local/share/opencode/repos" 2>/dev/null || true
}

teardown() {
  if [[ -n "${CONTAINER_NAME:-}" ]]; then
    podman rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    podman volume rm "$HOME_VOLUME" >/dev/null 2>&1 || true
  fi
  [[ -n "${WORKDIR:-}" ]] && rm -rf "$WORKDIR"
}

@test "[integration] fix_home_ownership makes volume writable by dev user" {
  fix_home_ownership

  run podman exec -u dev "$CONTAINER_NAME" sh -c 'stat -c %u /home/dev/.local/share/opencode'
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}

@test "[integration] dev user can create directories without EACCES after fix_home_ownership" {
  fix_home_ownership

  run podman exec -u dev "$CONTAINER_NAME" sh -c 'mkdir -p /home/dev/.local/share/opencode/repos/stuff'
  [ "$status" -eq 0 ]
}

@test "[integration] fix_home_ownership is idempotent" {
  fix_home_ownership
  run fix_home_ownership
  [ "$status" -eq 0 ]

  run podman exec -u dev "$CONTAINER_NAME" sh -c 'stat -c %u /home/dev/.local/share/opencode/repos'
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}
