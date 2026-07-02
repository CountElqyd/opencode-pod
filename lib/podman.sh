#!/usr/bin/env bash
# Container lifecycle management for opencode-pod.
# Requires lib/toml.sh to be sourced first.
set -euo pipefail

OPCODE_POD_PREFIX="opencode-pod"

resolve_project() {
  local project_dir="${1:-$PWD}"

  if ! cd "$project_dir" 2>/dev/null; then
    echo "Error: cannot access directory: $project_dir" >&2
    return 1
  fi
  project_dir="$(pwd)"

  local config_file="$project_dir/opencode-pod.toml"

  if [[ ! -f "$config_file" ]]; then
    auto_detect_profile "$project_dir"
    return 0
  fi

  unset CONFIG_CONTAINER_IMAGE CONFIG_CONTAINER_USER CONFIG_CONTAINER_NAME 2>/dev/null || true
  parse_toml "$config_file" || return 1

  CONTAINER_IMAGE="${CONFIG_CONTAINER_IMAGE:-}"
  CONTAINER_USER="${CONFIG_CONTAINER_USER:-}"

  local raw_name
  if [[ -n "${CONFIG_CONTAINER_NAME:-}" ]]; then
    raw_name="$CONFIG_CONTAINER_NAME"
  else
    raw_name="$(basename "$project_dir")"
  fi
  raw_name="$(printf '%s' "$raw_name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
  raw_name="${raw_name#-}"
  raw_name="${raw_name%-}"
  if [[ -z "$raw_name" ]]; then
    raw_name="project"
  fi

  local path_hash
  if command -v sha256sum >/dev/null 2>&1; then
    path_hash="$(printf '%s' "$project_dir" | sha256sum | cut -c1-6)"
  elif command -v md5sum >/dev/null 2>&1; then
    path_hash="$(printf '%s' "$project_dir" | md5sum | cut -c1-6)"
  elif command -v cksum >/dev/null 2>&1; then
    path_hash="$(printf '%s' "$project_dir" | cksum | cut -d' ' -f1 | cut -c1-6)"
  else
    echo "Error: no hash tool found (sha256sum, md5sum, cksum)" >&2
    return 1
  fi

  CONTAINER_NAME="${OPCODE_POD_PREFIX}-${raw_name}-${path_hash}"
  HOME_VOLUME="${CONTAINER_NAME}-home"

  local state
  if state="$(podman container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)"; then
    CONTAINER_STATE="$state"
  else
    CONTAINER_STATE="nonexistent"
  fi

  export CONTAINER_IMAGE CONTAINER_USER CONTAINER_NAME HOME_VOLUME CONTAINER_STATE
  return 0
}

auto_detect_profile() {
  local project_dir="${1:-$PWD}"

  if [[ -f "$project_dir/package.json" ]]; then
    AUTO_DETECTED_PROFILE="nodejs"
    AUTO_DETECTED_PACKAGES="nodejs npm git openssh"
  elif [[ -f "$project_dir/pyproject.toml" ]] || [[ -f "$project_dir/requirements.txt" ]]; then
    AUTO_DETECTED_PROFILE="python"
    AUTO_DETECTED_PACKAGES="python3 uv git openssh"
  elif [[ -f "$project_dir/Cargo.toml" ]]; then
    AUTO_DETECTED_PROFILE="rust"
    AUTO_DETECTED_PACKAGES="rust cargo git openssh"
  elif [[ -f "$project_dir/go.mod" ]]; then
    AUTO_DETECTED_PROFILE="go"
    AUTO_DETECTED_PACKAGES="go git openssh"
  else
    AUTO_DETECTED_PROFILE="default"
    AUTO_DETECTED_PACKAGES="git openssh curl"
  fi

  export AUTO_DETECTED_PROFILE AUTO_DETECTED_PACKAGES
}

classify_error() {
  local operation="${1:-unknown}"
  local exit_code="${2:-1}"
  local stderr_output="${3:-}"

  case "$operation" in
    podman_not_found|which_podman)
      printf '%s\n' "ERROR: Podman is not installed." >&2
      printf '%s\n' "Install with: (see opencode-pod doctor for OS-specific instructions)" >&2
      return 1
      ;;
    image_pull|podman_pull)
      printf '%s\n' "ERROR: Failed to pull Wolfi base image from cgr.dev." >&2
      printf '%s\n' "Check your internet connection, or re-run with a cached image." >&2
      return 1
      ;;
    podman_create)
      if printf '%s' "$stderr_output" | grep -qi "address already in use"; then
        printf '%s\n' "ERROR: Port is in use. Choose a different port in [network.forward]." >&2
        return 1
      fi
      if printf '%s' "$stderr_output" | grep -qi "no space"; then
        printf '%s\n' "ERROR: Not enough disk space. Need at least 2GB free." >&2
        printf '%s\n' "Clean old containers: opencode-pod doctor" >&2
        return 1
      fi
      if printf '%s' "$stderr_output" | grep -qi "SELinux\|selinux\|avc"; then
        printf '%s\n' "ERROR: SELinux blocked container access to the project directory." >&2
        printf '%s\n' "Run: restorecon -Rv $(pwd)" >&2
        return 1
      fi
      if printf '%s' "$stderr_output" | grep -qi "subuid\|subgid\|user namespace"; then
        printf '%s\n' "ERROR: Rootless Podman requires subuid/subgid configuration." >&2
        printf '%s\n' "Run 'opencode-pod doctor' for setup instructions." >&2
        return 1
      fi
      printf '%s\n' "ERROR: Container creation failed (exit code ${exit_code})." >&2
      printf '%s\n' "Run 'opencode-pod doctor' to diagnose." >&2
      return 1
      ;;
    apk_add)
      if printf '%s' "$stderr_output" | grep -qi "network\|unreachable\|temporary failure"; then
        printf '%s\n' "ERROR: Package install failed — could not reach Wolfi package repos." >&2
        printf '%s\n' "Run 'opencode-pod doctor' to verify container networking." >&2
        return 1
      fi
      if printf '%s' "$stderr_output" | grep -qi "not found\|404"; then
        printf '%s\n' "ERROR: Package not found in Wolfi repos." >&2
        printf '%s\n' "Check package name spelling in opencode-pod.toml" >&2
        return 1
      fi
      printf '%s\n' "ERROR: Package install failed (exit code ${exit_code})." >&2
      printf '%s\n' "Check opencode-pod.toml package names and try again." >&2
      return 1
      ;;
    toml_parse)
      printf '%s\n' "ERROR: Could not parse opencode-pod.toml" >&2
      printf '%s\n' "Run 'opencode-pod init' to regenerate a valid config." >&2
      return 1
      ;;
    *)
      printf '%s\n' "ERROR: Unexpected error during '${operation}' (exit code ${exit_code})." >&2
      printf '%s\n' "Run 'opencode-pod doctor' to diagnose." >&2
      return 1
      ;;
  esac
}

BOOTSTRAP_PROGRESS_FILE="/home/dev/.bootstrap-progress"

is_bootstrap_step_done() {
  local progress_file="$1"
  local step="$2"
  [[ -f "$progress_file" ]] && grep -qxF "$step" "$progress_file"
}

mark_bootstrap_step() {
  local progress_file="$1"
  local step="$2"
  printf '%s\n' "$step" >> "$progress_file"
}

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

run_bootstrap() {
  local progress="/tmp/.bootstrap-progress-${CONTAINER_NAME}"
  podman cp "$CONTAINER_NAME:${BOOTSTRAP_PROGRESS_FILE}" "$progress" 2>/dev/null || true
  touch "$progress"

  local completed_all=true

  if ! is_bootstrap_step_done "$progress" "packages_installed"; then
    local packages="${CONFIG_CONTAINER_PACKAGES:-git openssh curl} nodejs npm"
    printf '%s\n' "Installing packages: $packages"
    local apk_stderr
    apk_stderr="$(mktemp)"
    podman exec "$CONTAINER_NAME" apk add -U --no-cache $packages 2>"$apk_stderr" || true
    local stderr_text
    stderr_text="$(cat "$apk_stderr")"
    rm -f "$apk_stderr"

    # Verify each package actually installed (apk exit code is unreliable due to triggers)
    local missing=""
    for pkg in $packages; do
      if ! podman exec "$CONTAINER_NAME" apk info -e "$pkg" &>/dev/null; then
        missing="${missing}${missing:+ }${pkg}"
      fi
    done

    if [[ -z "$missing" ]]; then
      mark_bootstrap_step "$progress" "packages_installed"
    else
      printf '%s\n' "$stderr_text" >&2
      printf 'ERROR: Failed to install: %s\n' "$missing" >&2
      classify_error "apk_add" 1 "$stderr_text" >&2
      completed_all=false
    fi
  fi

  if ! is_bootstrap_step_done "$progress" "user_created"; then
    printf '%s\n' "Creating user: dev"
    if ! podman exec "$CONTAINER_NAME" sh -c "id dev 2>/dev/null || ( sed -i '/^[^:]*:[^:]*:1000:/d' /etc/passwd && sed -i '/^[^:]*:[^:]*:1000:/d' /etc/group && adduser -D -u 1000 dev)"; then
      printf '%s\n' "Failed to create dev user. Container may need --force-recreate." >&2
      completed_all=false
    else
      mark_bootstrap_step "$progress" "user_created"
    fi
  fi

  if ! is_bootstrap_step_done "$progress" "ssh_key_generated"; then
    printf '%s\n' "Generating SSH key..."
    if ! podman exec "$CONTAINER_NAME" sh -c "mkdir -p /home/dev/.ssh && ssh-keygen -t ed25519 -f /home/dev/.ssh/id_ed25519 -N '' -C 'opencode-pod'"; then
      printf '%s\n' "Failed to generate SSH key." >&2
      completed_all=false
    else
      mark_bootstrap_step "$progress" "ssh_key_generated"
    fi
  fi

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

  if ! is_bootstrap_step_done "$progress" "opencode_installed"; then
    printf '%s\n' "Installing opencode..."
    if podman exec "$CONTAINER_NAME" npm install -g opencode-ai; then
      mark_bootstrap_step "$progress" "opencode_installed"
    else
      printf '%s\n' "Failed to install opencode. Check network access." >&2
      completed_all=false
    fi
  fi

  podman cp "$progress" "$CONTAINER_NAME:${BOOTSTRAP_PROGRESS_FILE}" 2>/dev/null || true
  rm -f "$progress"

  # Fix home dir ownership — all root-run steps (ssh_keygen, config_copy, npm -g)
  # create root-owned files inside /home/dev. --cap-drop=ALL strips CAP_CHOWN,
  # so this must run from the host side via podman unshare, not inside the
  # container. Runs after ALL steps so dev can write to ~/.ssh, ~/.local,
  # ~/.npm, ~/.cache at runtime.
  if ! fix_home_ownership; then
    completed_all=false
  fi

  if ! $completed_all; then
    printf '%s\n' "Bootstrap incomplete. Re-run 'opencode-pod setup' to resume from checkpoint." >&2
    printf '%s\n' "Or use --force-recreate to destroy and start fresh." >&2
    return 1
  fi

  printf '%s\n' "Bootstrap complete."
  return 0
}

container_create() {
  local stderr_file
  stderr_file="$(mktemp)"

  local -a args=()
  args+=(create)
  args+=(--name "$CONTAINER_NAME")
  args+=(--volume "${HOME_VOLUME}:/home/dev")
  args+=(--volume "$(pwd):/workspace:Z")
  args+=(--userns=keep-id)
  args+=(--cap-drop=ALL)
  args+=(--security-opt=no-new-privileges)
  args+=(--hostname opencode-pod)

  local network_mode="${CONFIG_NETWORK_MODE:-bridge}"
  if [[ "$network_mode" == "none" ]]; then
    args+=(--network=none)
  elif [[ "$network_mode" == "host" ]]; then
    args+=(--network=host)
  fi

  local ports="${CONFIG_NETWORK_FORWARD:-}"
  if [[ -n "$ports" ]]; then
    for port in $ports; do
      args+=(-p "127.0.0.1:${port}:${port}")
    done
  fi

  local extra_mounts="${CONFIG_MOUNTS_EXTRA:-}"
  if [[ -n "$extra_mounts" ]]; then
    for mount in $extra_mounts; do
      mount="${mount/#\~/$HOME}"
      args+=(-v "$mount")
    done
  fi

  while IFS='=' read -r varname varval; do
    if [[ "$varname" == CONFIG_ENV_* ]]; then
      local envkey="${varname#CONFIG_ENV_}"
      envkey="$(printf '%s' "$envkey" | tr '[:upper:]' '[:lower:]')"
      args+=(--env "${envkey}=${varval}")
    fi
  done < <(env | grep '^CONFIG_ENV_')

  args+=("${CONFIG_CONTAINER_IMAGE:-cgr.dev/chainguard/wolfi-base:latest}")
  args+=(sleep infinity)

  if podman "${args[@]}" 2>"$stderr_file"; then
    rm -f "$stderr_file"
    return 0
  else
    local rc=$?
    cat "$stderr_file" >&2
    printf '%s' "$stderr_file"
    return $rc
  fi
}

container_setup() {
  if [[ "$CONTAINER_STATE" == "running" ]]; then
    printf '%s\n' "Container already set up and running: $CONTAINER_NAME"
    return 0
  fi

  if [[ "$CONTAINER_STATE" != "nonexistent" ]]; then
    printf '%s\n' "Container already exists (state: $CONTAINER_STATE). Use 'opencode-pod start' to reattach." >&2
    return 0
  fi

  printf '%s\n' "Setting up container: $CONTAINER_NAME"
  podman volume create "$HOME_VOLUME" 2>/dev/null || true

  local stderr_file
  if ! stderr_file="$(container_create)"; then
    local rc=$?
    local stderr_text=""
    [[ -f "$stderr_file" ]] && stderr_text="$(cat "$stderr_file")" && rm -f "$stderr_file"
    classify_error "podman_create" "$rc" "$stderr_text" >&2
    return $rc
  fi

  podman start "$CONTAINER_NAME" || return 1

  run_bootstrap

  printf '%s\n' "Container ready. Run 'opencode-pod start' to enter."
}

container_start() {
  if [[ "$CONTAINER_STATE" == "running" ]]; then
    printf '%s\n' "Reattaching to running container: $CONTAINER_NAME"
    fix_home_ownership || true
    podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /bin/sh
    return 0
  fi

  if [[ "$CONTAINER_STATE" == "paused" ]] || [[ "$CONTAINER_STATE" == "exited" ]]; then
    printf '%s\n' "Starting existing container: $CONTAINER_NAME"
    podman start "$CONTAINER_NAME" || return 1
    sleep 1
    run_bootstrap
    podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /bin/sh
    return 0
  fi

  printf '%s\n' "Container not set up. Run 'opencode-pod setup' first." >&2
  return 1
}

container_stop() {
  if [[ "$CONTAINER_STATE" == "nonexistent" ]]; then
    printf '%s\n' "No container found for this project." >&2
    return 1
  fi
  printf '%s\n' "Stopping container: $CONTAINER_NAME"
  podman stop "$CONTAINER_NAME" || return 1
}

container_shell() {
  if [[ "$CONTAINER_STATE" != "running" ]]; then
    printf '%s\n' "Container is not running. Run 'opencode-pod start' first." >&2
    return 1
  fi
  podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it -u dev --workdir /workspace "$CONTAINER_NAME" /bin/sh
}

container_destroy() {
  if [[ "$CONTAINER_STATE" == "nonexistent" ]]; then
    printf '%s\n' "No container found for this project." >&2
    return 1
  fi
  printf '%s\n' "Destroying container: $CONTAINER_NAME"
  podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
  podman volume rm "$HOME_VOLUME" 2>/dev/null || true
  printf '%s\n' "Container and home volume removed."
}
