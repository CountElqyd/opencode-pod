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

classify_error() { printf '%s\n' "Error: $1" >&2; return 1; }
run_bootstrap() { printf '%s\n' "Bootstrap not yet implemented." >&2; return 0; }

container_create_command() {
  local cmd="podman create"
  cmd="$cmd --name $CONTAINER_NAME"
  cmd="$cmd --volume ${HOME_VOLUME}:/home/dev"
  cmd="$cmd --volume $(pwd):/workspace:Z"
  cmd="$cmd --userns=keep-id"
  cmd="$cmd --cap-drop=ALL"
  cmd="$cmd --security-opt=no-new-privileges"
  cmd="$cmd --hostname opencode-pod"

  local network_mode="${CONFIG_NETWORK_MODE:-bridge}"
  if [[ "$network_mode" == "none" ]]; then
    cmd="$cmd --network=none"
  elif [[ "$network_mode" == "host" ]]; then
    cmd="$cmd --network=host"
  fi

  local ports="${CONFIG_NETWORK_FORWARD:-}"
  if [[ -n "$ports" ]]; then
    for port in $ports; do
      cmd="$cmd -p 127.0.0.1:${port}:${port}"
    done
  fi

  local extra_mounts="${CONFIG_MOUNTS_EXTRA:-}"
  if [[ -n "$extra_mounts" ]]; then
    for mount in $extra_mounts; do
      mount="${mount/#\~/$HOME}"
      cmd="$cmd -v $mount"
    done
  fi

  if [[ -n "${CONFIG_ENV:-}" ]]; then
    while IFS='=' read -r varname varval; do
      if [[ "$varname" == CONFIG_ENV_* ]]; then
        local envkey="${varname#CONFIG_ENV_}"
        envkey="$(printf '%s' "$envkey" | tr '[:upper:]' '[:lower:]')"
        cmd="$cmd --env ${envkey}=${varval}"
      fi
    done < <(env | grep '^CONFIG_ENV_')
  fi

  cmd="$cmd ${CONFIG_CONTAINER_IMAGE:-cgr.dev/chainguard/wolfi-base:latest}"
  cmd="$cmd /bin/sh"

  printf '%s' "$cmd"
}

container_start() {
  if [[ "$CONTAINER_STATE" == "running" ]]; then
    printf '%s\n' "Reattaching to running container: $CONTAINER_NAME"
    podman exec -it "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it "$CONTAINER_NAME" /bin/sh
    return 0
  fi

  if [[ "$CONTAINER_STATE" == "paused" ]] || [[ "$CONTAINER_STATE" == "exited" ]]; then
    printf '%s\n' "Starting existing container: $CONTAINER_NAME"
    podman start "$CONTAINER_NAME"
    podman exec -it "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it "$CONTAINER_NAME" /bin/sh
    return 0
  fi

  printf '%s\n' "Creating container: $CONTAINER_NAME"
  podman volume create "$HOME_VOLUME" 2>/dev/null || true

  local create_cmd
  create_cmd="$(container_create_command)"
  if ! eval "$create_cmd"; then
    classify_error "podman_create" "$?" "" >&2
    return 1
  fi

  podman start "$CONTAINER_NAME"

  run_bootstrap

  podman exec -it "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it "$CONTAINER_NAME" /bin/sh
}

container_stop() {
  if [[ "$CONTAINER_STATE" == "nonexistent" ]]; then
    printf '%s\n' "No container found for this project." >&2
    return 1
  fi
  printf '%s\n' "Stopping container: $CONTAINER_NAME"
  podman stop "$CONTAINER_NAME"
}

container_shell() {
  if [[ "$CONTAINER_STATE" != "running" ]]; then
    printf '%s\n' "Container is not running. Run 'opencode-pod start' first." >&2
    return 1
  fi
  podman exec -it "$CONTAINER_NAME" /usr/bin/zsh 2>/dev/null || podman exec -it "$CONTAINER_NAME" /bin/sh
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
