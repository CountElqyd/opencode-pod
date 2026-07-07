#!/usr/bin/env bash
# TOML parser for flat, single-level sections with dotted key support.
# Parses a TOML file and exports each key as CONFIG_SECTION_KEY=value.
# Arrays are space-joined. Values are unquoted.

CACHE_DIR="${CACHE_DIR:-${HOME}/.cache/opencode-pod}"

parse_toml() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    echo "Error: config file not found: $config_file" >&2
    return 1
  fi

  mkdir -p "$CACHE_DIR"

  local config_hash
  config_hash="$(printf '%s' "$config_file" | sha256sum 2>/dev/null | cut -c1-12)"
  if [[ -z "$config_hash" ]]; then
    config_hash="$(printf '%s' "$config_file" | md5sum 2>/dev/null | cut -c1-12 || printf '%s' "$config_file" | cksum | cut -d' ' -f1)"
  fi
  local cache_file="${CACHE_DIR}/opencode-pod-config-${config_hash}"

  local mtime
  mtime="$(stat -c %Y "$config_file" 2>/dev/null || stat -f %m "$config_file" 2>/dev/null)"

  if [[ -f "$cache_file" ]]; then
    local cached_mtime
    cached_mtime="$(head -n 1 "$cache_file" 2>/dev/null)"
    if [[ "$cached_mtime" == "$mtime" ]]; then
      # shellcheck disable=SC1090
      source <(tail -n +2 "$cache_file")
      return 0
    fi
  fi

  local current_section=""
  local line_number=0
  local array_values=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))

    # Strip inline comments (but not inside strings)
    local stripped
    stripped="$(printf '%s' "${line%%#*}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    [[ -z "$stripped" ]] && continue

    # Section header
    if [[ "$stripped" =~ ^\[([^\]]+)\]$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      if [[ "$current_section" =~ [^a-zA-Z0-9_.-] ]]; then
        echo "Error: invalid section name at line ${line_number}: [${current_section}]" >&2
        return 1
      fi
      # Normalize dots and hyphens to underscores for shell variable names
      current_section="${current_section//./_}"
      current_section="${current_section//-/_}"
      continue
    fi

    # Key = value
    if [[ "$stripped" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local value="${BASH_REMATCH[2]}"

      # Array value
      if [[ "$value" =~ ^\[(.*)\]$ ]]; then
        local inner="${BASH_REMATCH[1]}"
        inner="$(printf '%s' "$inner" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        if [[ -z "$inner" ]]; then
          array_values=""
        else
          # Split by commas, strip quotes from each element
          array_values=""
          IFS=',' read -ra elements <<< "$inner"
          for elem in "${elements[@]}"; do
            elem="$(printf '%s' "$elem" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            elem="${elem#\"}"
            elem="${elem%\"}"
            array_values="${array_values}${array_values:+ }${elem}"
          done
        fi
        value="$array_values"
      else
        # Strip surrounding quotes from string values
        if [[ "$value" =~ ^\"(.*)\"$ ]]; then
          value="${BASH_REMATCH[1]}"
        fi
      fi

      # Boolean values remain as-is
      local varname
      if [[ -n "$current_section" ]]; then
        varname="CONFIG_$(printf '%s' "${current_section}_${key}" | tr '[:lower:]' '[:upper:]')"
      else
        varname="CONFIG_$(printf '%s' "${key}" | tr '[:lower:]' '[:upper:]')"
      fi

      # Use printf -v for safe variable assignment
      printf -v "$varname" '%s' "$value"
      export "${varname?}"
    else
      echo "Error: could not parse ${config_file} at line ${line_number}: ${line}" >&2
      return 1
    fi
  done < "$config_file"

  {
    printf '%s\n' "$mtime"
    while IFS='=' read -r varname _; do
      if [[ "$varname" == CONFIG_* ]]; then
        printf 'export %s="%s"\n' "$varname" "${!varname}"
      fi
    done < <(env | sort | grep '^CONFIG_')
  } > "$cache_file"

  return 0
}
