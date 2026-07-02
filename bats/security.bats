#!/usr/bin/env bats

@test "security_flags includes cap-drop=ALL" {
  source lib/security.sh
  local flags
  flags="$(security_flags)"
  [[ "$flags" == *"--cap-drop=ALL"* ]]
}

@test "security_flags includes no-new-privileges" {
  source lib/security.sh
  local flags
  flags="$(security_flags)"
  [[ "$flags" == *"--security-opt=no-new-privileges"* ]]
}

@test "security_flags includes userns=keep-id" {
  source lib/security.sh
  local flags
  flags="$(security_flags)"
  [[ "$flags" == *"--userns=keep-id"* ]]
}

@test "opencode_config_path returns container path" {
  source lib/security.sh
  local path
  path="$(opencode_config_path)"
  [[ "$path" == *"/home/dev/.local/share/opencode/opencode.json"* ]]
}
