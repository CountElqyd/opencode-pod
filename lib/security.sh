#!/usr/bin/env bash
# Security hardening and configuration for opencode-pod containers.

set -euo pipefail

security_flags() {
  printf '%s' "--cap-drop=ALL --security-opt=no-new-privileges --userns=keep-id"
}

opencode_config_path() {
  printf '%s' "/home/dev/.local/share/opencode/opencode.json"
}
