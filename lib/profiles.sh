#!/usr/bin/env bash
# Profile management for opencode-pod.
# Commands: list, info, install, update.
# Sourced by the main opencode-pod CLI entry point.

OPCODE_POD_REPO="${OPCODE_POD_REPO:-CountElqyd/opencode-pod}"
OPCODE_POD_VERSION="${OPCODE_POD_VERSION:-main}"

github_raw_url() {
  printf 'https://raw.githubusercontent.com/%s/%s' "$OPCODE_POD_REPO" "$OPCODE_POD_VERSION"
}

_profile_registry_path() {
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}"
  printf '%s/opencode-pod/profiles.json' "$data_dir"
}

_load_registry() {
  local path
  path="$(_profile_registry_path)"
  if [[ ! -f "$path" ]]; then
    printf '{"format_version":1,"profiles":[]}'
    return
  fi
  cat "$path"
}

_save_registry() {
  local data="$1"
  local path
  path="$(_profile_registry_path)"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$data" > "$path"
}

_fetch_index() {
  local url
  url="$(github_raw_url)/profiles/index.json"
  curl -sS --fail "$url" 2>/dev/null
}

_profile_by_name() {
  local name="$1"
  local index_json="$2"
  printf '%s\n' "$index_json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
name = sys.argv[1]
for p in data.get("profiles", []):
    if p.get("name") == name:
        print(json.dumps(p))
        sys.exit(0)
sys.exit(1)
' "$name" 2>/dev/null || true
}

cmd_profile_list() {
  local index
  index=$(_fetch_index) || {
    printf 'Error: Unable to fetch profile index from GitHub.\n' >&2
    exit 1
  }

  local registry
  registry=$(_load_registry)

  printf '%-20s %-8s %-10s %s\n' 'NAME' 'VERSION' 'INSTALLED' 'DESCRIPTION'
  printf '%s\n' "$index" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(2)

registry = json.loads(sys.argv[1]) if sys.argv[1] else {"profiles": []}
registry_map = {p["name"]: p.get("version", "?") for p in registry.get("profiles", [])}

for p in data.get("profiles", []):
    name = p.get("name", "?")
    ver = p.get("version", "?")
    desc = p.get("description", "")
    installed = registry_map.get(name, "\u2014")
    print(f"{name:<20} {ver:<8} {installed:<10} {desc}")
' "$registry" 2>/dev/null || {
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

  local index
  index=$(_fetch_index) || {
    printf 'Error: Unable to fetch profile index from GitHub.\n' >&2
    exit 1
  }

  local profile_json
  profile_json=$(_profile_by_name "$name" "$index")
  if [[ -z "$profile_json" ]]; then
    printf '%s\n' "$index" | python3 -c 'import sys,json; json.load(sys.stdin)' 2>/dev/null || {
      printf 'Error: Invalid profile index format.\n' >&2
      exit 1
    }
    printf "Profile '%s' not found. Run 'opencode-pod profile list'.\n" "$name" >&2
    exit 1
  fi

  local registry installed_ver=""
  registry=$(_load_registry)
  installed_ver=$(printf '%s\n' "$registry" | python3 -c "
import sys, json
data = json.load(sys.stdin)
name = '$name'
for p in data.get('profiles', []):
    if p.get('name') == name:
        print(p.get('version', ''))
" 2>/dev/null || printf '')

  printf '%s\n' "$profile_json" | python3 -c '
import sys, json
data = json.load(sys.stdin)
name = data.get("name", "")
ver = data.get("version", "")
desc = data.get("description", "")
author = data.get("author", "")
components = data.get("components", {})
requires = data.get("requires", [])
network = data.get("network", "")
installed = "'"$installed_ver"'"

print(f"Profile:            {name}")
print(f"Version:            {ver}")
if installed and installed != ver:
    print(f"  (installed: {installed})")
elif installed:
    print(f"Installed:          {installed}")
if author:
    print(f"Author:             {author}")
print(f"Description:        {desc}")
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
' 2>/dev/null || {
    printf 'Error: Invalid profile metadata format.\n' >&2
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
