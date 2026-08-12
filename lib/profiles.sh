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

# --- Declarative toml requirements ---

# Print the profile's declared toml requirements as JSON, merging the legacy
# `network` field (alias for toml.network.mode) with the `toml` block.
# The `toml` block wins if both are present. Empty legacy network is ignored.
# Usage: _declared_toml_requirements <profile_json>
_declared_toml_requirements() {
  printf '%s\n' "$1" | python3 -c '
import sys, json
try:
    p = json.load(sys.stdin)
except json.JSONDecodeError:
    print("Invalid profile json: expected a JSON object", file=sys.stderr)
    sys.exit(1)
if not isinstance(p, dict):
    print("Invalid profile json: expected an object", file=sys.stderr)
    sys.exit(1)
toml_block = p.get("toml")
if toml_block is not None and not isinstance(toml_block, dict):
    print("Invalid profile toml block: expected an object", file=sys.stderr)
    sys.exit(1)
req = dict(toml_block or {})
legacy = p.get("network")
if legacy and not isinstance(legacy, str):
    print("Invalid profile network field: expected a string", file=sys.stderr)
    sys.exit(1)
if legacy and "network" not in req:
    req["network"] = {"mode": legacy}
print(json.dumps(req))
'
}

# Validate declared requirements against the v1 allowlist. Prints the (valid)
# requirements JSON on stdout and returns 0, or an error to stderr and 1.
# v1 allowlist is scalar-string values only; arrays are rejected.
# Usage: _validate_toml_requirements <requirements_json>
_validate_toml_requirements() {
  printf '%s\n' "$1" | python3 -c '
import sys, json
ALLOW = {"network": {"mode"}, "mounts": {"extra"}, "container": {"packages"}}
try:
    req = json.load(sys.stdin)
except json.JSONDecodeError:
    print("Invalid requirements json: expected a JSON object", file=sys.stderr)
    sys.exit(1)
if not isinstance(req, dict):
    print("Invalid requirements json: expected an object", file=sys.stderr)
    sys.exit(1)
for section, sub in req.items():
    if not isinstance(sub, dict):
        print(f"Invalid toml requirement section: [{section}] expected an object", file=sys.stderr)
        sys.exit(1)
    if section == "env":
        for k, v in sub.items():
            if any(ord(c) < 32 for c in k):
                print(f"Unsupported toml key [env.{k}]: control characters are not supported in v1", file=sys.stderr)
                sys.exit(1)
            if not isinstance(v, str):
                print(f"Unsupported value for toml key [env.{k}]: v1 supports scalar strings only", file=sys.stderr)
                sys.exit(1)
            if any(ord(c) < 32 for c in v):
                print(f"Unsupported value for toml key [env.{k}]: control characters are not supported in v1", file=sys.stderr)
                sys.exit(1)
        continue
    if section not in ALLOW:
        print(f"Unknown toml requirement section: [{section}]", file=sys.stderr)
        sys.exit(1)
    for k, v in sub.items():
        if k not in ALLOW[section]:
            print(f"Unknown toml requirement key: [{section}.{k}]", file=sys.stderr)
            sys.exit(1)
        if isinstance(v, list):
            print(f"Unsupported value for toml key [{section}.{k}]: arrays are not supported in v1", file=sys.stderr)
            sys.exit(1)
        if not isinstance(v, str):
            print(f"Unsupported value for toml key [{section}.{k}]: v1 supports scalar strings only", file=sys.stderr)
            sys.exit(1)
        if any(ord(c) < 32 for c in v):
            print(f"Unsupported value for toml key [{section}.{k}]: control characters are not supported in v1", file=sys.stderr)
            sys.exit(1)
print(json.dumps(req))
'
}

# Returns 0 if stdin is a terminal. Test hook — override in bats.
_interactive() {
  [[ -t 0 ]]
}

# Print unit-separator (\x1f) delta lines for declared requirements that differ
# from the current opencode-pod.toml: "section\x1fkey\x1fcurrent\x1fdeclared".
# \x1f is not IFS whitespace, so empty middle fields survive a read. Missing
# current values print as empty. If tomllib is unavailable or the toml
# is unparsable, every declared key is reported as differing (documented
# degradation — the caller's prompt/apply path still works).
# Usage: _toml_deltas <requirements_json>
_toml_deltas() {
  python3 -c '
import sys, json
try:
    import tomllib
    with open("opencode-pod.toml", "rb") as f:
        cur = tomllib.load(f)
except Exception:
    cur = {}
try:
    req = json.load(sys.stdin)
except Exception:
    print("Invalid toml requirements: malformed JSON", file=sys.stderr)
    sys.exit(1)
if not isinstance(req, dict):
    print("Invalid toml requirements: expected an object", file=sys.stderr)
    sys.exit(1)

def norm(val):
    if val is None:
        return ""
    if val is True:
        return "true"
    if val is False:
        return "false"
    return str(val)

for section, sub in req.items():
    for k, v in sub.items():
        sec = cur.get(section)
        curv = sec.get(k) if isinstance(sec, dict) else None
        normv = norm(curv)
        if normv != v:
            print(f"{section}\x1f{k}\x1f{normv}\x1f{v}")
' <<< "$1"
}

# Set a scalar key within a toml section, preserving comments and sibling
# lines. Adds the key to an existing section, or appends a new section.
# v1: writes double-quoted string values only.
# Usage: _toml_set <toml_file> <section> <key> <value>
_toml_set() {
  local file="$1" section="$2" key="$3" value="$4"
  if [[ -L "$file" ]]; then
    file="$(readlink -f "$file")"
  fi
  [[ -f "$file" ]] || : > "$file"
  local tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  # shellcheck disable=SC2064
  if [[ -n "${BASH_VERSION:-}" ]]; then
    trap 'rm -f "$tmp"' RETURN
  fi
  local value_esc key_esc
  value_esc="${value//\\/\\\\}"
  value_esc="${value_esc//\"/\\\"}"
  key_esc="$(printf '%s\n' "$key" | awk '{ gsub(/[][\\^$.*?+(){|}]/, "\\\\&"); print }')"
  local in_section=false found_section=false wrote=false pending=false
  local sec_pat key_pat hdr
  sec_pat='^\[[^]]+\][[:space:]]*(#.*)?$'
  key_pat="^${key_esc}[[:space:]]*="
  while IFS= builtin read -r line; do
    if [[ "$line" =~ $sec_pat ]]; then
      if $pending; then
        printf '%s = "%s"\n' "$key" "$value_esc" >> "$tmp"
        pending=false
      fi
      hdr="$(printf '%s\n' "$line" | sed -n 's/^\[\([^]]*\)\].*/\1/p')"
      hdr="${hdr#"${hdr%%[![:space:]]*}"}"
      hdr="${hdr%"${hdr##*[![:space:]]}"}"
      if [[ "$hdr" == "$section" ]]; then
        in_section=true
        found_section=true
      else
        in_section=false
      fi
    fi
    if $in_section && [[ "$line" =~ $key_pat ]]; then
      printf '%s = "%s"\n' "$key" "$value_esc" >> "$tmp"
      wrote=true
      pending=false
      continue
    fi
    printf '%s\n' "$line" >> "$tmp"
    if $in_section && ! $wrote; then
      pending=true
    fi
  done < "$file"
  if ! $wrote; then
    if ! $found_section; then
      printf '\n[%s]\n' "$section" >> "$tmp"
      printf '%s = "%s"\n' "$key" "$value_esc" >> "$tmp"
    elif $pending; then
      printf '%s = "%s"\n' "$key" "$value_esc" >> "$tmp"
    fi
  fi
  if [[ -f "$file" ]]; then
    chmod --reference="$file" "$tmp"
  fi
  mv "$tmp" "$file"
}

# Apply a profile's declared toml requirements to opencode-pod.toml.
# Exit codes: 0 = no change needed/applied; 1 = hard error (invalid block,
# non-TTY, or recreate failure); 2 = deltas applied (+ container recreated);
# 3 = deltas existed but the user declined.
# v1 allowlist is entirely recreate-class, so any applied delta recreates.
# Usage: _apply_toml_requirements <profile_json>
_apply_toml_requirements() {
  local profile_json="$1"
  local req deltas

  req="$(_declared_toml_requirements "$profile_json")" || return 1
  [[ -z "$req" || "$req" == "{}" ]] && return 0

  req="$(_validate_toml_requirements "$req")" || return 1

  deltas="$(_toml_deltas "$req")" || { printf 'Error: failed to compute toml requirements diff.\n' >&2; return 1; }
  [[ -z "$deltas" ]] && return 0

  if ! _interactive; then
    printf 'Error: profile toml requirements cannot be applied without a terminal.\n' >&2
    printf '  Run interactively to confirm container recreation.\n' >&2
    return 1
  fi

  printf 'Profile requires the following opencode-pod.toml changes:\n'
  while IFS=$'\x1f' builtin read -r section key curval newval; do
    printf '  [%s.%s]: %s -> %s\n' "$section" "$key" "${curval:-<absent>}" "$newval"
  done <<< "$deltas"

  printf 'Apply and recreate the container? [y/N]: '
  local RESPONSE
  read -r RESPONSE
  if [[ ! "$RESPONSE" =~ ^[yY] ]]; then
    return 3
  fi

  while IFS=$'\x1f' builtin read -r section key curval newval; do
    _toml_set "opencode-pod.toml" "$section" "$key" "$newval"
  done <<< "$deltas"

  # Re-parse the config so container creation uses the newly written values.
  # mtime-cached parse_toml refreshes CONFIG_* on the updated file.
  if declare -f parse_toml >/dev/null 2>&1; then
    parse_toml "opencode-pod.toml" >/dev/null 2>&1 || true
  fi

  printf '  Destroying container...\n'
  container_destroy || true
  CONTAINER_STATE="nonexistent"
  printf '  Recreating container...\n'
  container_setup || {
    printf 'Error: Container recreate failed.\n' >&2
    return 1
  }
  podman start "$CONTAINER_NAME" || {
    printf 'Error: Failed to start recreated container.\n' >&2
    return 1
  }
  sleep 1
  CONTAINER_STATE="running"
  return 2
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

  local version description sha256_value
  version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')
  sha256_value=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || printf '')

  _apply_toml_requirements "$profile_json"
  local apply_rc=$?
  if [[ $apply_rc -eq 3 ]]; then
    printf 'Install cancelled.\n'
    exit 1
  elif [[ $apply_rc -eq 1 ]]; then
    exit 1
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

  local new_version new_description new_sha256
  new_version=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("version","?"))' 2>/dev/null)
  new_description=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("description",""))' 2>/dev/null || printf '')
  new_sha256=$(printf '%s\n' "$profile_json" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("sha256",""))' 2>/dev/null || printf '')

  local apply_rc=0
  _apply_toml_requirements "$profile_json" || apply_rc=$?
  if [[ $apply_rc -eq 3 ]]; then
    printf 'Warning: profile toml requirements not applied (declined).\n' >&2
  elif [[ $apply_rc -eq 1 ]]; then
    printf 'Warning: failed to apply profile toml requirements.\n' >&2
  fi

  # A recreate (apply_rc=2) wiped the container home volume and registry via
  # container_destroy, so the profile must be reinstalled even when the
  # version is unchanged — do not take the "already at" shortcut.
  if [[ $apply_rc -ne 2 ]] && [[ "$installed_version" == "$new_version" ]] && ! $force; then
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

  printf "Profile '%s' updated to v%s.\n" "$name" "$new_version"
}
