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

  local tmp_dir="/tmp/.opencode-profile-${name}"

  podman exec -u dev "$CONTAINER_NAME" sh -c "
    TMP='${tmp_dir}'
    mkdir -p \"\$TMP\" && cd \"\$TMP\"
    trap 'rm -rf \"\$TMP\"' EXIT
    set -e
    curl -sS --fail -O '${tarball_url}' && curl -sS --fail -O '${setup_url}'
    chmod +x setup.sh
    bash setup.sh
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

  local version network_mode description
  version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  network_mode=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("network",""))' 2>/dev/null || printf '')
  description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')

  if [[ "$network_mode" == "host" && -t 0 ]]; then
    local response
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

  local tarball_url setup_url
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"

  printf "Installing profile '%s' (v%s) inside container...\n" "$name" "$version"

  if ! _container_exec_setup "$name" "$tarball_url" "$setup_url"; then
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
  if [[ ! -d "./profiles/${name}" ]]; then
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

  local new_version new_network new_description old_version old_network
  new_version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  new_network=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("network",""))' 2>/dev/null || printf '')
  new_description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')

  if [[ -f "./profiles/${name}/profile.json" ]]; then
    old_version=$(python3 -c 'import sys,json; print(json.load(open(sys.argv[1])).get("version","?"))' "./profiles/${name}/profile.json" 2>/dev/null || printf '?')
    old_network=$(python3 -c 'import sys,json; print(json.load(open(sys.argv[1])).get("network",""))' "./profiles/${name}/profile.json" 2>/dev/null || printf '')
  else
    old_version="?"
    old_network=""
  fi

  if [[ "$old_version" == "$new_version" ]] && ! $force; then
    printf "Profile '%s' is already at v%s. Use --force to re-download.\n" "$name" "$new_version"
    return 0
  fi

  printf "Updating '%s': v%s → v%s\n" "$name" "$old_version" "$new_version"

  # Backup existing files
  local backup_dir
  backup_dir="$(mktemp -d)"
  trap 'rm -rf "$backup_dir"' EXIT
  cp "./profiles/${name}/${name}.tar.gz" "$backup_dir/" 2>/dev/null || true
  cp "./profiles/${name}/setup.sh" "$backup_dir/" 2>/dev/null || true

  # Download new files
  local tarball_url setup_url dl_failed=false
  tarball_url="$(github_raw_url)/profiles/${name}/${name}.tar.gz"
  if ! curl -sS --fail -o "./profiles/${name}/${name}.tar.gz" "$tarball_url" 2>/dev/null; then
    dl_failed=true
  fi

  setup_url="$(github_raw_url)/profiles/${name}/setup.sh"
  if ! curl -sS --fail -o "./profiles/${name}/setup.sh" "$setup_url" 2>/dev/null; then
    dl_failed=true
  fi

  if $dl_failed; then
    # Restore from backup
    cp "$backup_dir/${name}.tar.gz" "./profiles/${name}/" 2>/dev/null || true
    cp "$backup_dir/setup.sh" "./profiles/${name}/" 2>/dev/null || true
    rm -rf "$backup_dir"
    printf 'Error: Failed to download profile archive. Restored previous version.\n' >&2
    exit 1
  fi
  rm -rf "$backup_dir"

  chmod +x "./profiles/${name}/setup.sh"

  # Save updated profile.json
  printf '%s\n' "$profile_json" > "./profiles/${name}/profile.json"

  # Update registry
  local registry
  registry=$(_load_registry)
  local updated_registry
  updated_registry=$(printf '%s\n' "$registry" | python3 -c '
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
name = sys.argv[1]
version = sys.argv[2]
desc = sys.argv[3]
path = "profiles/" + name + "/"
new_entry = {"name": name, "version": version, "description": desc, "path": path, "installed_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")}
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
  if [[ -n "$updated_registry" ]]; then
    _save_registry "$updated_registry"
  fi

  # Handle network mode changes
  if [[ -n "$new_network" && "$new_network" != "$old_network" && -t 0 ]]; then
    local response
    printf 'Network mode changed (%s → %s). Update opencode-pod.toml? [y/N]: ' "$old_network" "$new_network"
    read -r response
    if [[ "$response" =~ ^[yY] ]]; then
      if [[ -f "opencode-pod.toml" ]]; then
        sed -i '/^\[network\]/,/^\[/{s/mode = ".*"/mode = "'"$new_network"'"/}' "opencode-pod.toml"
        printf 'Updated network mode to %s in opencode-pod.toml.\n' "$new_network"
      fi
    fi
  fi

  printf "Profile '%s' updated to v%s.\n" "$name" "$new_version"
  printf "To re-install inside the container, run:\n"
  printf "  bash profiles/%s/setup.sh\n" "$name"
}
