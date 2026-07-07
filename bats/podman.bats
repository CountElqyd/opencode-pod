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
  mkdir -p "$TESTDIR/project"
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

  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_args"; return 0; }
  container_create

  local cmd
  cmd="$(cat "$TESTDIR/podman_args")"
  [[ "$cmd" == *"create"* ]]
  [[ "$cmd" == *"--name ${CONTAINER_NAME}"* ]]
  [[ "$cmd" == *"--volume ${HOME_VOLUME}:/home/dev"* ]]
  [[ "$cmd" == *"--userns=keep-id"* ]]
  [[ "$cmd" == *"--cap-drop=ALL"* ]]
  [[ "$cmd" == *"--security-opt=no-new-privileges"* ]]
  [[ "$cmd" == *"-p 127.0.0.1:3000:3000"* ]]
}

@test "container_create adds network mode when specified" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"

[network]
mode = "none"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_args"; return 0; }
  container_create

  local cmd
  cmd="$(cat "$TESTDIR/podman_args")"
  [[ "$cmd" == *"--network=none"* ]]
}

@test "container_create defaults to network bridge" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_args"; return 0; }
  container_create

  local cmd
  cmd="$(cat "$TESTDIR/podman_args")"
  [[ "$cmd" != *"--network=none"* ]]
  [[ "$cmd" != *"--network=host"* ]]
}

@test "container_create adds extra mounts" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"

[mounts]
extra = ["~/.npmrc:/home/dev/.npmrc:ro"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_args"; return 0; }
  container_create

  local cmd
  cmd="$(cat "$TESTDIR/podman_args")"
  [[ "$cmd" == *"-v ${HOME}/.npmrc:/home/dev/.npmrc:ro"* ]]
}

@test "classify_error matches PODMAN_NOT_FOUND" {
  source lib/podman.sh
  run classify_error "podman_not_found" 0 "" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Podman is not installed"* ]]
}

@test "classify_error matches IMAGE_PULL_FAILED" {
  source lib/podman.sh
  run classify_error "image_pull" 1 "" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to pull"* ]]
}

@test "classify_error matches PORT_CONFLICT from stderr" {
  source lib/podman.sh
  run classify_error "podman_create" 1 "address already in use" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"in use"* ]]
}

@test "classify_error matches DISK_SPACE_LOW from stderr" {
  source lib/podman.sh
  run classify_error "podman_create" 1 "no space left on device" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"disk space"* ]]
}

@test "classify_error handles unknown error" {
  source lib/podman.sh
  run classify_error "unknown_thing" 1 "" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unexpected error"* ]]
}

@test "is_bootstrap_step_done detects completed step" {
  source lib/podman.sh
  local tmpfile
  tmpfile="$(mktemp)"
  printf '%s\n' "packages_installed" > "$tmpfile"
  printf '%s\n' "user_created" >> "$tmpfile"

  run is_bootstrap_step_done "$tmpfile" "packages_installed"
  [ "$status" -eq 0 ]

  run is_bootstrap_step_done "$tmpfile" "ssh_key_generated"
  [ "$status" -ne 0 ]

  rm -f "$tmpfile"
}

@test "mark_bootstrap_step writes step" {
  source lib/podman.sh
  local tmpfile
  tmpfile="$(mktemp)"

  mark_bootstrap_step "$tmpfile" "packages_installed"
  grep -q "packages_installed" "$tmpfile"

  rm -f "$tmpfile"
}

# --- setup command ---

@test "container_start errors when container not set up" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  run container_start 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"not set up"* || "$output" == *"No container"* ]]
}

@test "container_setup function exists" {
  source lib/podman.sh
  type container_setup >/dev/null 2>&1
  [ "$?" -eq 0 ] || [ "$(type -t container_setup)" = "function" ]
}

@test "container_setup skips when container already exists and running" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  # Simulate container already exists
  CONTAINER_STATE="running"

  run container_setup 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* || "$output" == *"exists"* ]]
}

@test "bootstrap marks packages_installed despite apk exit 1" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git", "zsh"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() {
    case "$1" in
      start) return 0 ;;
      exec)
        if [[ "$2" == "$CONTAINER_NAME" && "$3" == "apk" && "$4" == "add" ]]; then
          return 1
        fi
        if [[ "$2" == "$CONTAINER_NAME" && "$3" == "apk" && "$4" == "info" ]]; then
          return 0
        fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap reports missing packages" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git", "nonexistent-pkg"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  podman() {
    case "$1" in
      start) return 0 ;;
      exec)
        if [[ "$2" == "$CONTAINER_NAME" && "$3" == "apk" && "$4" == "add" ]]; then
          return 1
        fi
        if [[ "$2" == "$CONTAINER_NAME" && "$3" == "apk" && "$4" == "info" ]]; then
          [[ "$6" == "nonexistent-pkg" ]] && return 1
          return 0
        fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"nonexistent-pkg"* ]]
}

@test "bootstrap installs opencode via npm" {
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
      exec)
        if [[ "$*" == *"id dev"* ]]; then return 0; fi
        if [[ "$*" == *"ssh-keygen"* ]]; then return 0; fi
        if [[ "$*" == *"apk"* ]]; then return 0; fi
        if [[ "$*" == *"npm install"* ]]; then return 0; fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing opencode"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap opencode step is skipped if already done" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  # Pre-populate progress file with all steps done including opencode
  local progress="/tmp/.bootstrap-progress-${CONTAINER_NAME}"
  printf 'packages_installed\nuser_created\nssh_key_generated\nnvm_installed\nopencode_config_copied\nopencode_installed\n' > "$progress"

  podman() {
    case "$1" in
      start) return 0 ;;
      cp)
        if [[ "$*" == *".bootstrap-progress" ]]; then
          mkdir -p "$(dirname "$3")" 2>/dev/null || true
          cp "$progress" "$3"
        fi
        return 0
        ;;
      exec) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" != *"Installing opencode"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]

  rm -f "$progress"
}

@test "bootstrap opencode failure is handled" {
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
      exec)
        if [[ "$*" == *"id dev"* ]]; then return 0; fi
        if [[ "$*" == *"ssh-keygen"* ]]; then return 0; fi
        if [[ "$*" == *"apk info"* ]]; then return 0; fi
        if [[ "$*" == *"npm"* ]]; then return 1; fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"Bootstrap incomplete"* ]]
  [[ "$output" == *"opencode"* ]]
}

@test "bootstrap installs nvm and LTS node for dev user" {
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
      exec)
        if [[ "$*" == *"id dev"* ]]; then return 0; fi
        if [[ "$*" == *"ssh-keygen"* ]]; then return 0; fi
        if [[ "$*" == *"apk"* ]]; then return 0; fi
        if [[ "$*" == *"bash -c"* ]]; then return 0; fi
        if [[ "$*" == *"npm install"* ]]; then return 0; fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installing nvm"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap nvm step is skipped if already done" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
packages = ["git"]
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  local progress="/tmp/.bootstrap-progress-${CONTAINER_NAME}"
  printf 'packages_installed\nuser_created\nssh_key_generated\nnvm_installed\n' > "$progress"

  podman() {
    case "$1" in
      start) return 0 ;;
      cp)
        if [[ "$*" == *".bootstrap-progress" ]]; then
          mkdir -p "$(dirname "$3")" 2>/dev/null || true
          cp "$progress" "$3"
        fi
        return 0
        ;;
      exec) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -eq 0 ]
  [[ "$output" != *"Installing nvm"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]

  rm -f "$progress"
}

@test "bootstrap nvm failure blocks bootstrap" {
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
      exec)
        if [[ "$*" == *"id dev"* ]]; then return 0; fi
        if [[ "$*" == *"ssh-keygen"* ]]; then return 0; fi
        if [[ "$*" == *"apk"* ]]; then return 0; fi
        if [[ "$*" == *"bash -c"* ]]; then return 1; fi
        if [[ "$*" == *"npm install"* ]]; then return 0; fi
        return 0
        ;;
      cp) return 0 ;;
    esac
    return 0
  }
  export -f podman

  run run_bootstrap
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"*"nvm"* ]]
  [[ "$output" == *"Bootstrap incomplete"* ]]
}

@test "container_start reattaches to running container after setup" {
  mkdir -p "$TESTDIR/project"
  cat > "$TESTDIR/project/opencode-pod.toml" << 'EOF'
[container]
image = "wolfi-base"
EOF

  source lib/toml.sh
  source lib/podman.sh
  resolve_project "$TESTDIR/project"

  # Force state to running
  CONTAINER_STATE="running"

  podman() { return 0; }
  export -f podman

  run container_start 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Reattaching"* ]]
}

@test "container_start execs as dev user" {
  source lib/podman.sh
  CONTAINER_NAME="test"
  CONTAINER_STATE="running"
  podman() { printf '%s\n' "$*" > "$TESTDIR/podman_args"; return 0; }
  container_start
  local cmd
  cmd="$(cat "$TESTDIR/podman_args")"
  [[ "$cmd" == *"-u dev"* ]]
}

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

@test "run_bootstrap calls fix_home_ownership at the beginning" {
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

@test "run_bootstrap completes despite fix_home_ownership failure" {
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
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: could not resolve home volume mountpoint"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]
}

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
  [[ "$output" == *"failed to copy opencode config"* ]]
}

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
