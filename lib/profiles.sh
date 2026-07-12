#!/usr/bin/env bash
# Profile management for opencode-pod.
# Commands: list, info, install, update.
# Sourced by the main opencode-pod CLI entry point.

OPCODE_POD_REPO="${OPCODE_POD_REPO:-CountElqyd/opencode-pod}"
OPCODE_POD_VERSION="${OPCODE_POD_VERSION:-main}"

github_raw_url() {
  printf 'https://raw.githubusercontent.com/%s/%s' "$OPCODE_POD_REPO" "$OPCODE_POD_VERSION"
}

cmd_profile_list() {
  local url
  url="$(github_raw_url)/profiles/index.json"

  local json
  json=$(curl -sS --fail "$url" 2>/dev/null) || {
    printf 'Error: Unable to fetch profile index from GitHub.\n' >&2
    exit 1
  }

  printf '%-20s %-10s %s\n' 'NAME' 'VERSION' 'DESCRIPTION'
  printf '%s\n' "$json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(2)
for p in data.get("profiles", []):
    name = p.get("name", "?")
    ver = p.get("version", "?")
    desc = p.get("description", "")
    print(f"{name:<20} {ver:<10} {desc}")
' || {
    local rc=$?
    if [[ $rc -eq 2 ]]; then
      printf 'Error: Invalid profile index format.\n' >&2
    fi
    exit 1
  }
}

cmd_profile_info() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    printf 'Usage: opencode-pod profile info <name>\n' >&2
    exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Error: Invalid profile name. Use alphanumeric, dash, underscore.\n' >&2
    exit 1
  fi

  local url
  url="$(github_raw_url)/profiles/${name}/profile.json"

  local json
  json=$(curl -sS --fail "$url" 2>/dev/null) || {
    printf "Profile '%s' not found. Run 'opencode-pod profile list'.\n" "$name" >&2
    exit 1
  }

  printf '%s\n' "$json" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(2)
name = data.get("name", "")
ver = data.get("version", "")
desc = data.get("description", "")
author = data.get("author", "")
components = data.get("components", {})
requires = data.get("requires", [])
network = data.get("network", "")
print(f"Profile:            {name}")
print(f"Version:            {ver}")
print(f"Description:        {desc}")
if author:
    print(f"Author:             {author}")
print("Components:")
comp_labels = {
    "skills": "Skills:",
    "agents": "Agents:",
    "commands": "Commands:",
    "fabric_mcp": "Fabric MCP:",
    "gsd_core": "GSD Core:",
}
for key, label in comp_labels.items():
    if key in components:
        val = components[key]
        if isinstance(val, bool):
            val = "true" if val else "false"
        print(f"  {label:<16} {val}")
if requires:
    _comma = ", "
    print(f"Requires:           {_comma.join(requires)}")
if network:
    print(f"Network:            {network}")
' || {
    local rc=$?
    if [[ $rc -eq 2 ]]; then
      printf 'Error: Invalid profile metadata format.\n' >&2
    fi
    exit 1
  }
}

cmd_profile_install() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    printf 'Usage: opencode-pod profile install <name>\n' >&2
    exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Error: Invalid profile name. Use alphanumeric, dash, underscore.\n' >&2
    exit 1
  fi

  if [[ -d "./profiles/${name}" ]]; then
    printf "Already installed. Run 'opencode-pod profile update %s' to re-download.\n" "$name" >&2
    exit 1
  fi

  local url json version network_mode
  url="$(github_raw_url)/profiles/${name}/profile.json"
  json=$(curl -sS --fail "$url" 2>/dev/null) || {
    printf "Profile '%s' not found. Run 'opencode-pod profile list'.\n" "$name" >&2
    exit 1
  }

  version=$(printf '%s\n' "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
print(data.get("version", "?"))
' 2>/dev/null) || {
    printf 'Error: Invalid profile metadata format.\n' >&2
    exit 1
  }

  network_mode=$(printf '%s\n' "$json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
print(data.get("network", ""))
' 2>/dev/null || printf '')

  mkdir -p "./profiles/${name}"

  local tarball_url
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  if ! curl -sS --fail -o "./profiles/${name}/${name}.tar.gz" "$tarball_url" 2>/dev/null; then
    rm -rf "./profiles/${name}"
    printf 'Error: Failed to download profile archive.\n' >&2
    exit 1
  fi

  local setup_url
  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"
  if ! curl -sS --fail -o "./profiles/${name}/setup.sh" "$setup_url" 2>/dev/null; then
    rm -rf "./profiles/${name}"
    printf 'Error: Failed to download setup script.\n' >&2
    exit 1
  fi

  chmod +x "./profiles/${name}/setup.sh"

  if [[ "$network_mode" == "host" && -t 0 ]]; then
    printf 'Profile requires host networking. Update opencode-pod.toml? [y/N]: '
    read -r response
    if [[ "$response" =~ ^[yY] ]]; then
      if [[ -f "opencode-pod.toml" ]]; then
        sed -i '/^\[network\]/,/^\[/{s/mode = "bridge"/mode = "host"/}' "opencode-pod.toml"
        printf 'Updated network mode to host in opencode-pod.toml.\n'
      else
        printf 'No opencode-pod.toml found. Set [network] mode = "host" manually.\n' >&2
      fi
    fi
  fi

  printf "Profile '%s' (v%s) installed.\n" "$name" "$version"
  printf "To install inside the container, run:\n"
  printf "  bash profiles/%s/setup.sh\n" "$name"
}

cmd_profile_update() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    printf 'Usage: opencode-pod profile update <name>\n' >&2
    exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Error: Invalid profile name. Use alphanumeric, dash, underscore.\n' >&2
    exit 1
  fi

  if [[ ! -d "./profiles/${name}" ]]; then
    printf "Profile not found. Run 'opencode-pod profile install %s' first.\n" "$name" >&2
    exit 1
  fi

  local tarball_url
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  if ! curl -sS --fail -o "./profiles/${name}/${name}.tar.gz" "$tarball_url" 2>/dev/null; then
    printf 'Error: Failed to download profile archive.\n' >&2
    exit 1
  fi

  local setup_url
  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"
  if ! curl -sS --fail -o "./profiles/${name}/setup.sh" "$setup_url" 2>/dev/null; then
    printf 'Error: Failed to download setup script.\n' >&2
    exit 1
  fi

  chmod +x "./profiles/${name}/setup.sh"

  printf "Profile '%s' updated.\n" "$name"
}
