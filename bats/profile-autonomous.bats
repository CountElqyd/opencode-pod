#!/usr/bin/env bats

setup_file() {
  TESTDIR="$(mktemp -d)"
  export BATS_TEST_DIRNAME_TARBALL="$TESTDIR"
  cp -r "$BATS_TEST_DIRNAME/../profiles/autonomous/src" "$TESTDIR/src"
  rm -f "$TESTDIR/src/config/gsd-config.json"
  echo "0.1.0" > "$TESTDIR/VERSION"
  tar czf "$TESTDIR/autonomous.tar.gz" \
    -C "$TESTDIR/src" config/ skills/ agents/ commands/ plugins/ \
    -C "$TESTDIR" VERSION
}

teardown_file() {
  [[ -n "${BATS_TEST_DIRNAME_TARBALL:-}" ]] && rm -rf "$BATS_TEST_DIRNAME_TARBALL"
}

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"
  mkdir -p "$HOME/.config/opencode"
}

teardown() {
  rm -rf "${TEST_HOME:-}"
}

# --- setup.sh idempotency ---

@test "setup.sh idempotency guard skips when already installed" {
  echo "0.1.0" > "$HOME/.autonomous-version"
  echo "original" > "$HOME/.config/opencode/opencode.json"

  local profiledir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  [ "$(cat "$HOME/.config/opencode/opencode.json")" = "original" ]
  rm -rf "$profiledir"
}

# --- setup.sh graphify / uv handling ---

@test "setup.sh self-installs uv when missing and installs graphify" {
  local profiledir mockdir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  mkdir -p "$mockdir/payload/foo"
  cat > "$mockdir/payload/foo/uv" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "tool" && "$2" == "install" && "$3" == "graphifyy==0.9.41" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\necho graphify 0.1.0\n' > "$HOME/.local/bin/graphify"
  chmod +x "$HOME/.local/bin/graphify"
  echo "uv tool install graphifyy OK" > "$mockdir/uv-call.log"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "$mockdir/payload/foo/uv"
  tar czf "$mockdir/uv.tar.gz" -C "$mockdir/payload" foo/

  cat > "$mockdir/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat "$MOCK_UV_TARBALL"
SCRIPT
  chmod +x "$mockdir/curl"

  cat > "$mockdir/npx" <<'SCRIPT'
#!/usr/bin/env bash
echo "gsd installed (mock)" > "$mockdir/npx-call.log"
exit 0
SCRIPT
  chmod +x "$mockdir/npx"

  command() {
    case "$*" in
      *"graphify"*)
        return 1
        ;;
      *"uv"*)
        local resolved
        resolved="$(builtin command -v uv 2>/dev/null || true)"
        if [[ -n "$resolved" && "$resolved" != "$HOME/.local/bin/uv" ]]; then
          return 1
        fi
        ;;
    esac
    builtin command "$@"
  }
  export -f command

  export MOCK_UV_TARBALL="$mockdir/uv.tar.gz"
  export mockdir

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/uv" ]
  [ -f "$mockdir/uv-call.log" ]
  [ -f "$mockdir/npx-call.log" ]
  [ -f "$HOME/.autonomous-version" ]
  [ "$(cat "$HOME/.autonomous-version")" = "0.1.0" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "setup.sh uses existing uv without re-download" {
  local profiledir mockdir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  cat > "$mockdir/uv" <<'SCRIPT'
#!/usr/bin/env bash
echo "uv called: $*" >> "$mockdir/uv-call.log"
if [[ "$1" == "tool" && "$2" == "install" && "$3" == "graphifyy==0.9.41" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\necho graphify 0.1.0\n' > "$HOME/.local/bin/graphify"
  chmod +x "$HOME/.local/bin/graphify"
fi
exit 0
SCRIPT
  chmod +x "$mockdir/uv"

  cat > "$mockdir/curl" <<'SCRIPT'
#!/usr/bin/env bash
touch "$mockdir/curl-called"
exit 0
SCRIPT
  chmod +x "$mockdir/curl"

  cat > "$mockdir/npx" <<'SCRIPT'
#!/usr/bin/env bash
echo "gsd installed (mock)" > "$mockdir/npx-call.log"
exit 0
SCRIPT
  chmod +x "$mockdir/npx"

  command() {
    if [[ "$*" == *"graphify"* ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command

  export mockdir

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$mockdir/curl-called" ]
  [ -f "$mockdir/uv-call.log" ]
  [ -f "$HOME/.local/bin/graphify" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "autocode command replaces launch-ralph with full pipeline" {
  local dir="$BATS_TEST_DIRNAME/../profiles/autonomous/src/commands"
  [ -f "$dir/autocode.md" ]
  [ ! -f "$dir/launch-ralph.md" ]
  grep -q 'argument-hint: "\[design-doc\]' "$dir/autocode.md"
  grep -q -- "--watch" "$dir/autocode.md"
  grep -q -- "--timeout" "$dir/autocode.md"
  grep -q -- "--prepare-only" "$dir/autocode.md"
  grep -q -- "--skip-prepare" "$dir/autocode.md"
  grep -q "autocode-decider" "$dir/autocode.md"
  grep -q "No design doc found" "$dir/autocode.md"
  grep -q "gsd-autonomous" "$dir/autocode.md"
  grep -q "agent: autocode-runner" "$dir/autocode.md"
}

@test "autocode discovers design artifact package across conventions" {
  local dir="$BATS_TEST_DIRNAME/../profiles/autonomous/src/commands"
  grep -q -- "latest" "$dir/autocode.md"
  grep -q -- '\*-design-doc.md' "$dir/autocode.md"
  grep -q -- "docs/specs" "$dir/autocode.md"
  grep -q -- "docs/plans" "$dir/autocode.md"
  grep -q -- "package" "$dir/autocode.md"
  grep -q -- "newest" "$dir/autocode.md"
  grep -q -- "provenance" "$dir/autocode.md"
}

@test "autocode-runner forbids question and mandates decider dispatch" {
  local runner="$BATS_TEST_DIRNAME/../profiles/autonomous/src/agents/autocode-runner.md"
  [ -f "$runner" ]
  grep -q 'NEVER call the .question. tool' "$runner"
  grep -q "autocode-decider" "$runner"
  grep -q "{choice, rationale}" "$runner"
}

@test "autocode-runner composes the design package" {
  local runner="$BATS_TEST_DIRNAME/../profiles/autonomous/src/agents/autocode-runner.md"
  grep -q -- "package" "$runner"
  grep -q -- "provenance" "$runner"
}

@test "autocode-decider policy table covers all decision types" {
  local decider="$BATS_TEST_DIRNAME/../profiles/autonomous/src/agents/autocode-decider.md"
  [ -f "$decider" ]
  grep -q "grey areas" "$decider"
  grep -q "accept recommended answers" "$decider"
  grep -q "blocker" "$decider"
  grep -q "retry once" "$decider"
  grep -q "skip the phase" "$decider"
  grep -q "human_needed verification" "$decider"
  grep -q "validation deferred" "$decider"
  grep -q "gaps found" "$decider"
  grep -q "gap closure once" "$decider"
  grep -q "audit gaps" "$decider"
  grep -q "tech debt" "$decider"
  grep -q "cleanup confirmation" "$decider"
  grep -q "approve" "$decider"
}

@test "opencode.json is valid JSON with modern permission schema" {
  local cfg="$BATS_TEST_DIRNAME/../profiles/autonomous/src/config/opencode.json"
  [ -f "$cfg" ]
  cfg="$cfg" python3 - <<'PY'
import json, os
cfg = json.load(open(os.environ['cfg']))
assert 'permission' in cfg, 'modern singular permission key required'
assert 'permissions' not in cfg, 'legacy plural permissions key must be removed'
p = cfg['permission']
assert p.get('external_directory') == {'*': 'allow'}
assert p.get('doom_loop') == 'allow'
assert p.get('webfetch') == 'allow'
assert p.get('websearch') == 'allow'
bash = p['bash']
assert bash['*'] == 'allow'
for deny in ['curl *', 'wget *', 'sudo *', 'su *', 'env', 'printenv *', 'printenv',
             'rm -rf*', 'rm -r*', 'rm --recursive*', 'git push*',
             'git push --force*', 'git push -f*', 'git remote add*',
             'git remote set-url*', 'git reset --hard*', 'git clean*',
             'git config alias*', 'npm publish*', 'pip install --system*',
             'pip3 install --system*', 'chmod 777 *', 'apk *', 'apt *',
             'apt-get *', 'brew *', 'yum *', 'dnf *', 'pacman *',
             'shred *', 'dd *', 'mkfs*']:
    assert bash.get(deny) == 'deny', f"bash deny missing: {deny}"
edit = p['edit']
assert edit['*'] == 'allow'
for deny in ['~/.ssh/**', '~/.aws/**', '~/.gnupg/**',
             '~/.config/opencode/opencode.json*',
             '~/.local/share/opencode/auth.json', '/etc/**', '/usr/**',
             '/bin/**', '/sbin/**', '/boot/**', '/sys/**', '/proc/**',
             '/dev/**', '*id_rsa*', '*.pem', '*.key']:
    assert edit.get(deny) == 'deny', f"edit deny missing: {deny}"
read = p['read']
assert read['*'] == 'allow'
for deny in ['*.env', '*.env.*', '~/.ssh/**', '~/.aws/**', '~/.gnupg/**',
             '~/.config/opencode/opencode.json*',
             '~/.local/share/opencode/auth.json', '*id_rsa*',
             '*.pem', '*.key', '/etc/shadow*', '/etc/passwd*']:
    assert read.get(deny) == 'deny', f"read deny missing: {deny}"
assert read.get('*.env.example') == 'allow'
agent = cfg['agent']
runner = agent['autocode-runner']
assert runner['mode'] == 'primary'
assert runner['steps'] == 150
assert runner['permission']['question'] == 'deny'
decider = agent['autocode-decider']
assert decider['mode'] == 'subagent'
assert decider['permission'].get('edit') == 'deny'
assert decider['permission'].get('bash') == 'deny'
assert cfg['compaction'] == {'auto': True, 'reserved': 10000}
print('ok')
PY
}

@test "gsd-config.json retains pre-seed alignment keys" {
  local cfg="$BATS_TEST_DIRNAME/../profiles/autonomous/src/config/gsd-config.json"
  [ -f "$cfg" ]
  cfg="$cfg" python3 - <<'PY'
import json, os
cfg = json.load(open(os.environ['cfg']))
w = cfg['workflow']
assert w['tdd_mode'] is True
assert w['use_worktrees'] is False
assert w['code_review'] is True
assert w['quality_gates']['enabled'] is False
assert cfg['graphify']['auto_update'] is True
assert 'gsd-executor' in cfg['agent_skills']
assert 'skip_discuss' not in cfg.get('workflow', {})
print('ok')
PY
}

@test "autonomous profile declares host networking via toml block" {
  local meta="$BATS_TEST_DIRNAME/../profiles/autonomous/profile.json"
  python3 -c "
import json
m = json.load(open('$meta'))
assert m['toml']['network']['mode'] == 'host', m
assert m.get('network') == 'host', m
"
  python3 -c "
import json
data = json.load(open('$BATS_TEST_DIRNAME/../profiles/index.json'))
p = [x for x in data['profiles'] if x['name'] == 'autonomous'][0]
assert p['version'] == '0.2.4', p
"
  python3 -c "
import hashlib, json, os, tarfile
base = '$BATS_TEST_DIRNAME/../'
index = json.load(open(os.path.join(base, 'profiles/index.json')))
p = [x for x in index['profiles'] if x['name'] == 'autonomous'][0]
tarball = os.path.join(base, 'profiles/autonomous/autonomous.tar.gz')
with open(tarball, 'rb') as f:
    actual = hashlib.sha256(f.read()).hexdigest()
assert actual == p['sha256'], ('sha256 mismatch', actual, p['sha256'])
with tarfile.open(tarball, 'r:gz') as tf:
    version = tf.extractfile('VERSION').read().decode().strip()
assert version == p['version'], ('VERSION mismatch', version, p['version'])
"
}

@test "graphify workflow artifacts are present in src" {
  local base="$BATS_TEST_DIRNAME/../profiles/autonomous/src"
  [ -f "$base/skills/graphify/SKILL.md" ]
  [ -d "$base/skills/graphify/references" ]
  [ -f "$base/skills/superpowers/context-management/SKILL.md" ]
  [ -f "$base/commands/new-project.md" ]
  [ -f "$base/commands/setup-project.md" ]
  [ -f "$base/plugins/graphify.js" ]
  grep -q 'graphify query' "$base/commands/new-project.md"
  grep -q 'Graphify First' "$base/commands/setup-project.md"
}

@test "setup-project deep-mode is deterministic, not interactive" {
  local cmd="$BATS_TEST_DIRNAME/../profiles/autonomous/src/commands/setup-project.md"
  [ -f "$cmd" ]
  grep -q 'ASK the user' "$cmd" && return 1
  grep -q 'mode deep' "$cmd"
  grep -q '\$ARGUMENTS' "$cmd"
}

@test "setup.sh installs plugins into .config/opencode/plugins" {
  local profiledir mockdir
  profiledir="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME_TARBALL/autonomous.tar.gz" "$profiledir/autonomous.tar.gz"
  cp "$BATS_TEST_DIRNAME/../profiles/autonomous/setup.sh" "$profiledir/setup.sh"
  chmod +x "$profiledir/setup.sh"

  mockdir="$(mktemp -d)"
  cat > "$mockdir/uv" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == "tool" && "$2" == "install" && "$3" == "graphifyy==0.9.41" ]]; then
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\necho graphify 0.1.0\n' > "$HOME/.local/bin/graphify"
  chmod +x "$HOME/.local/bin/graphify"
fi
exit 0
SCRIPT
  chmod +x "$mockdir/uv"
  cat > "$mockdir/npx" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod +x "$mockdir/npx"
  command() {
    if [[ "$*" == *"graphify"* ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  export mockdir

  PATH="$mockdir:$PATH" run bash "$profiledir/setup.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/opencode/plugins/graphify.js" ]
  rm -rf "$profiledir" "$mockdir"
}

@test "autonomous profile components reflect graphify workflow" {
  python3 -c "
import json
m = json.load(open('$BATS_TEST_DIRNAME/../profiles/autonomous/profile.json'))
c = m['components']
assert c['skills'] == 6, c
assert c['commands'] == 3, c
assert c['plugins'] == 1, c
"
}

@test "ported graphify skill retains command-coupled surface" {
  local skill="$BATS_TEST_DIRNAME/../profiles/autonomous/src/skills/graphify/SKILL.md"
  local hooks="$BATS_TEST_DIRNAME/../profiles/autonomous/src/skills/graphify/references/hooks.md"
  [ -f "$skill" ]
  [ -f "$hooks" ]
  grep -q -- '--update' "$skill"
  grep -q -- '--mode deep' "$skill"
  grep -q 'graphify query' "$skill"
  grep -q 'graphify-out/graph.json' "$skill"
  grep -q 'references/hooks.md' "$skill"
  grep -q 'graphify hook install' "$hooks"
}
