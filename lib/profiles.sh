#!/usr/bin/env bash
# Profile management for opencode-pod.
# Commands: list, info, install, update.
# Sourced by the main opencode-pod CLI entry point.

OPCODE_POD_REPO="${OPCODE_POD_REPO:-CountElqyd/opencode-pod}"
OPCODE_POD_VERSION="${OPCODE_POD_VERSION:-main}"

# shellcheck disable=SC1091
source "${LIB_DIR}/podman.sh" 2>/dev/null || true

_container_exec_setup() {
  local name="$1"
  local tarball_url="$2"
  local setup_url="$3"
  local expected_sha256="${4:-}"

  local host_tmp
  host_tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$host_tmp'" RETURN

  curl -sS --fail -o "$host_tmp/${name}.tar.gz" "$tarball_url" || {
    printf 'Error: Failed to download profile tarball for %s\n' "$name" >&2
    return 1
  }
  curl -sS --fail -o "$host_tmp/setup.sh" "$setup_url" || {
    printf 'Error: Failed to download profile setup for %s\n' "$name" >&2
    return 1
  }

  if [[ -n "$expected_sha256" ]]; then
    local actual_sha256
    actual_sha256="$(sha256sum "$host_tmp/${name}.tar.gz" | cut -d' ' -f1)"
    if [[ "$actual_sha256" != "$expected_sha256" ]]; then
      printf 'ERROR: Tarball checksum mismatch for profile %s\n' "$name" >&2
      printf '  Expected: %s\n' "$expected_sha256" >&2
      printf '  Got:      %s\n' "$actual_sha256" >&2
      return 1
    fi
  fi

  local container_tmp="/tmp/.opencode-profile-${name}"
  podman exec "$CONTAINER_NAME" mkdir -p "$container_tmp"
  podman cp "$host_tmp/${name}.tar.gz" "$CONTAINER_NAME:${container_tmp}/"
  podman cp "$host_tmp/setup.sh" "$CONTAINER_NAME:${container_tmp}/"

  podman exec -u dev "$CONTAINER_NAME" sh -c "
    cd '$container_tmp'
    chmod +x setup.sh
    bash setup.sh
    rm -rf '$container_tmp'
  "
}

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
  local force=false
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) name="$1"; shift ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Usage: opencode-pod profile install [--force] <name>\n' >&2
    exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Error: Invalid profile name. Use alphanumeric, dash, underscore.\n' >&2
    exit 1
  fi

  resolve_project || {
    printf "Error: Run 'opencode-pod setup' first.\n" >&2
    exit 1
  }

  if [[ "$CONTAINER_STATE" == "nonexistent" ]]; then
    printf "Error: Container not found. Run 'opencode-pod setup' first.\n" >&2
    exit 1
  fi

  local registry
  registry=$(_load_registry)
  local installed_version
  installed_version=$(printf '%s\n' "$registry" | python3 -c "
import sys, json
data = json.load(sys.stdin)
name = '$name'
for p in data.get('profiles', []):
    if p.get('name') == name:
        print(p.get('version', ''))
" 2>/dev/null || printf '')

  if [[ -n "$installed_version" ]] && ! $force; then
    printf "Already installed. Run 'opencode-pod profile update %s' or use --force.\n" "$name" >&2
    exit 1
  fi

  if [[ "$CONTAINER_STATE" != "running" ]]; then
    printf "Starting container %s...\n" "$CONTAINER_NAME"
    podman start "$CONTAINER_NAME" || {
      printf 'Error: Failed to start container.\n' >&2
      exit 1
    }
    sleep 1
    CONTAINER_STATE="running"
  fi

  local index
  index=$(_fetch_index) || {
    printf 'Error: Unable to fetch profile index from GitHub.\n' >&2
    exit 1
  }

  local profile_json
  profile_json=$(_profile_by_name "$name" "$index")
  if [[ -z "$profile_json" ]]; then
    printf "Profile '%s' not found. Run 'opencode-pod profile list'.\n" "$name" >&2
    exit 1
  fi

  local version network_mode description sha256_value
  version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  network_mode=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("network",""))' 2>/dev/null || printf '')
  description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')
  sha256_value=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || printf '')

  if [[ "$network_mode" == "host" ]]; then
    if [[ ! -t 0 ]]; then
      printf 'Error: Profile "%s" requires host networking but stdin is not a terminal.\n' "$name" >&2
      printf 'Run interactively to confirm container recreation.\n' >&2
      exit 1
    fi

    local current_network
    current_network="$(podman container inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER_NAME" 2>/dev/null || echo "nonexistent")"

    if [[ "$current_network" != "host" ]]; then
      printf 'Profile "%s" requires host networking (current: %s).\n' "$name" "$current_network"
      printf 'The container must be destroyed and recreated. Continue? [y/N]: '
      local response
      read -r response
      if [[ "$response" =~ ^[yY] ]]; then
        if [[ -f "opencode-pod.toml" ]]; then
          sed -i '/^\[network\]/,/^\[/{s/mode = ".*"/mode = "host"/}' "opencode-pod.toml"
          # shellcheck disable=SC2034 # used in podman.sh:container_create
          CONFIG_NETWORK_MODE="host"
          printf '  Updated network mode to host in opencode-pod.toml.\n'
        fi
        printf '  Destroying container...\n'
        container_destroy || true
        CONTAINER_STATE="nonexistent"
        printf '  Recreating container with host networking...\n'
        container_setup || {
          printf 'Error: Container recreate failed.\n' >&2
          exit 1
        }
        podman start "$CONTAINER_NAME" || {
          printf 'Error: Failed to start recreated container.\n' >&2
          exit 1
        }
        sleep 1
        CONTAINER_STATE="running"
      else
        printf 'Install cancelled.\n'
        exit 1
      fi
    fi
  fi

  local tarball_url setup_url
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"

  printf "Installing profile '%s' (v%s) inside container...\n" "$name" "$version"

  if ! _container_exec_setup "$name" "$tarball_url" "$setup_url" "$sha256_value"; then
    printf 'Error: Profile setup failed inside container.\n' >&2
    exit 1
  fi

  local updated_registry
  updated_registry=$(printf '%s\n' "$registry" | python3 -c '
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
name = sys.argv[1]
version = sys.argv[2]
desc = sys.argv[3]
new_entry = {"name": name, "version": version, "description": desc, "path": "", "installed_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}
profiles = data.get("profiles", [])
for i, p in enumerate(profiles):
    if p.get("name") == name:
        profiles[i] = new_entry
        break
else:
    profiles.append(new_entry)
data["profiles"] = profiles
print(json.dumps(data, indent=2))
' "$name" "$version" "$description" 2>/dev/null)
  if [[ -z "$updated_registry" ]]; then
    printf 'Warning: Failed to update profile registry.\n' >&2
  else
    _save_registry "$updated_registry"
  fi

  printf "Profile '%s' (v%s) installed inside container.\n" "$name" "$version"
}

cmd_profile_update() {
  local force=false
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true; shift ;;
      *) name="$1"; shift ;;
    esac
  done

  if [[ -z "$name" ]]; then
    printf 'Usage: opencode-pod profile update [--force] <name>\n' >&2
    exit 1
  fi
  if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Error: Invalid profile name. Use alphanumeric, dash, underscore.\n' >&2
    exit 1
  fi

  resolve_project || {
    printf "Error: Run 'opencode-pod setup' first.\n" >&2
    exit 1
  }

  if [[ "$CONTAINER_STATE" == "nonexistent" ]]; then
    printf "Error: Container not found. Run 'opencode-pod setup' first.\n" >&2
    exit 1
  fi

  local registry
  registry=$(_load_registry)
  local installed_version
  installed_version=$(printf '%s\n' "$registry" | python3 -c "
import sys, json
data = json.load(sys.stdin)
name = '$name'
for p in data.get('profiles', []):
    if p.get('name') == name:
        print(p.get('version', ''))
" 2>/dev/null || printf '')

  if [[ -z "$installed_version" ]]; then
    printf "Profile not found. Run 'opencode-pod profile install %s' first.\n" "$name" >&2
    exit 1
  fi

  local index profile_json
  index=$(_fetch_index) || {
    printf 'Error: Unable to fetch profile index from GitHub.\n' >&2
    exit 1
  }
  profile_json=$(_profile_by_name "$name" "$index")
  if [[ -z "$profile_json" ]]; then
    printf "Profile '%s' no longer available. Run 'opencode-pod profile list'.\n" "$name" >&2
    exit 1
  fi

  local new_version new_network new_description new_sha256
  new_version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  new_network=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("network",""))' 2>/dev/null || printf '')
  new_description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')
  new_sha256=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || printf '')

  if [[ "$installed_version" == "$new_version" ]] && ! $force; then
    printf "Profile '%s' is already at v%s. Use --force to re-install.\n" "$name" "$new_version"
    return 0
  fi

  printf "Updating '%s': v%s → v%s\n" "$name" "$installed_version" "$new_version"

  if [[ "$CONTAINER_STATE" != "running" ]]; then
    printf "Starting container %s...\n" "$CONTAINER_NAME"
    podman start "$CONTAINER_NAME" || {
      printf 'Error: Failed to start container.\n' >&2
      exit 1
    }
    sleep 1
    CONTAINER_STATE="running"
  fi

  local tarball_url setup_url
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"

  printf "Updating profile '%s' inside container...\n" "$name"

  if ! _container_exec_setup "$name" "$tarball_url" "$setup_url" "$new_sha256"; then
    printf 'Error: Profile update failed inside container.\n' >&2
    exit 1
  fi

  local updated_registry
  updated_registry=$(printf '%s\n' "$registry" | python3 -c '
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
name = sys.argv[1]
version = sys.argv[2]
desc = sys.argv[3]
new_entry = {"name": name, "version": version, "description": desc, "path": "", "installed_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}
profiles = data.get("profiles", [])
for i, p in enumerate(profiles):
    if p.get("name") == name:
        profiles[i] = new_entry
        break
else:
    profiles.append(new_entry)
data["profiles"] = profiles
print(json.dumps(data, indent=2))
' "$name" "$new_version" "$new_description" 2>/dev/null)
  if [[ -z "$updated_registry" ]]; then
    printf 'Warning: Failed to update profile registry.\n' >&2
  else
    _save_registry "$updated_registry"
  fi

  if [[ -n "$new_network" && -t 0 ]]; then
    local current_network
    current_network=$(python3 -c '
import sys, json
try:
    with open("opencode-pod.toml") as f:
        for line in f:
            line = line.strip()
            if line == "[network]":
                break
        for line in f:
            line = line.strip()
            if line.startswith("mode"):
                print(line.split("=", 1)[1].strip().strip("\"'\"'"))
                break
except Exception:
    pass
' 2>/dev/null || printf '')
    if [[ -n "$current_network" && "$current_network" != "$new_network" ]]; then
      local response
      printf 'Network mode changed (%s → %s). Update opencode-pod.toml? [y/N]: ' "$current_network" "$new_network"
      read -r response
      if [[ "$response" =~ ^[yY] ]]; then
        if [[ -f "opencode-pod.toml" ]]; then
          sed -i '/^\[network\]/,/^\[/{s/mode = ".*"/mode = "'"$new_network"'"/}' "opencode-pod.toml"
          printf 'Updated network mode to %s in opencode-pod.toml.\n' "$new_network"
        fi
      fi
    fi
  fi

  printf "Profile '%s' updated to v%s.\n" "$name" "$new_version"
}
