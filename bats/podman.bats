#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "resolve_project loads TOML config" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
user = "dev"
packages = ["git", "nodejs"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [ "$CONTAINER_IMAGE" = "cgr.dev/chainguard/wolfi-base:latest" ]
  [ "$CONTAINER_USER" = "dev" ]
}

@test "resolve_project derives container name from dirname" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [[ "$CONTAINER_NAME" == opencode-pod-project-* ]]
}

@test "resolve_project generates unique names for same dirname in different paths" {
  mkdir -p "$TESTDIR/a/myapp"
  mkdir -p "$TESTDIR/b/myapp"

  cat > "$TESTDIR/a/myapp/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF
  cat > "$TESTDIR/b/myapp/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/a/myapp"
  local name_a="$CONTAINER_NAME"

  resolve_project "$TESTDIR/b/myapp"
  local name_b="$CONTAINER_NAME"

  [ "$name_a" != "$name_b" ]
}

@test "resolve_project uses optional [container] name override" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
name = "myspecialapp"
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [[ "$CONTAINER_NAME" == opencode-pod-myspecialapp-* ]]
}

@test "resolve_project sets HOME_VOLUME name" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [[ "$HOME_VOLUME" == opencode-pod-*-home ]]
  [[ "$HOME_VOLUME" == *project* ]]
}

@test "resolve_project detects container state: nonexistent" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [ "$CONTAINER_STATE" = "nonexistent" ]
}

@test "resolve_project auto-detects project type when no config" {
  mkdir -p "$TESTDIR/project"
  touch "$TESTDIR/project/package.json"

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  [[ "$AUTO_DETECTED_PROFILE" == "nodejs" ]]
}

@test "container_create assembles correct podman create command" {
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
user = "dev"
packages = ["git", "nodejs"]

[network]
forward = [3000]

[security]
harden = true
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  local cmd
  cmd="$(container_create_command)"
  [[ "$cmd" == *"podman create"* ]]
  [[ "$cmd" == *"--name ${CONTAINER_NAME}"* ]]
  [[ "$cmd" == *"--volume ${HOME_VOLUME}:/home/dev"* ]]
  [[ "$cmd" == *"--userns=keep-id"* ]]
  [[ "$cmd" == *"--cap-drop=ALL"* ]]
  [[ "$cmd" == *"--security-opt=no-new-privileges"* ]]
  [[ "$cmd" == *"-p 127.0.0.1:3000:3000"* ]]
}

@test "container_create adds network mode when specified" {
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"

[network]
mode = "none"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  local cmd
  cmd="$(container_create_command)"
  [[ "$cmd" == *"--network=none"* ]]
}

@test "container_create defaults to network bridge" {
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  local cmd
  cmd="$(container_create_command)"
  [[ "$cmd" != *"--network=none"* ]]
  [[ "$cmd" != *"--network=host"* ]]
}

@test "container_create adds extra mounts" {
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"

[mounts]
extra = ["~/.npmrc:/home/dev/.npmrc:ro"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  local cmd
  cmd="$(container_create_command)"
  [[ "$cmd" == *"-v ${HOME}/.npmrc:/home/dev/.npmrc:ro"* ]]
}
