#!/usr/bin/env bash
# Security hardening and configuration for opencode-pod containers.

security_flags() {
  printf '%s' "--cap-drop=ALL --security-opt=no-new-privileges --userns=keep-id"
}

opencode_config_path() {
  local user="${1:-dev}"
  printf '/home/%s/.local/share/opencode/opencode.json' "$user"
}
