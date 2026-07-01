#!/usr/bin/env bash
# Container lifecycle management for opencode-pod.
# Requires lib/toml.sh to be sourced first.

OPCODE_POD_PREFIX="opencode-pod"

resolve_project() {
  local project_dir="${1:-$PWD}"
  project_dir="$(cd "$project_dir" && pwd)"

  local config_file="$project_dir/opencode-pod.toml"

  if [[ ! -f "$config_file" ]]; then
    auto_detect_profile "$project_dir"
    return 0
  fi

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

  local path_hash
  path_hash="$(printf '%s' "$project_dir" | sha256sum | cut -c1-6)"

  CONTAINER_NAME="${OPCODE_POD_PREFIX}-${raw_name}-${path_hash}"
  HOME_VOLUME="${CONTAINER_NAME}-home"

  if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
    CONTAINER_STATE="$(podman container inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || printf '%s' 'unknown')"
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
