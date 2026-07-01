#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "parses simple key-value pairs" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[container]
image = "cgr.dev/chainguard/wolfi-base:latest"
user = "dev"
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_CONTAINER_IMAGE" = "cgr.dev/chainguard/wolfi-base:latest" ]
  [ "$CONFIG_CONTAINER_USER" = "dev" ]
}

@test "parses array values" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[container]
packages = ["nodejs", "npm", "git"]
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_CONTAINER_PACKAGES" = "nodejs npm git" ]
}

@test "parses boolean values" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[security]
http = false
harden = true
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_SECURITY_HTTP" = "false" ]
  [ "$CONFIG_SECURITY_HARDEN" = "true" ]
}

@test "parses port forward list" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[network]
forward = [3000, 8080]
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_NETWORK_FORWARD" = "3000 8080" ]
}

@test "parses extra mounts" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[mounts]
extra = ["~/.npmrc:/home/dev/.npmrc:ro"]
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_MOUNTS_EXTRA" = "~/.npmrc:/home/dev/.npmrc:ro" ]
}

@test "handles empty config gracefully" {
  touch "$TESTDIR/config.toml"

  source lib/toml.sh
  run parse_toml "$TESTDIR/config.toml"

  [ "$status" -eq 0 ]
}

@test "handles missing config file" {
  source lib/toml.sh
  run parse_toml "$TESTDIR/nonexistent.toml"

  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "handles comments" {
  cat > "$TESTDIR/config.toml" << 'EOF'
# This is a comment
[container]
image = "wolfi-base"  # inline comment
# another comment
user = "dev"
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_CONTAINER_IMAGE" = "wolfi-base" ]
  [ "$CONFIG_CONTAINER_USER" = "dev" ]
}

@test "handles values with equals signs" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[env]
GREETING = "hello=world"
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_ENV_GREETING" = "hello=world" ]
}

@test "reports error with line number for malformed TOML" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[container]
image = "wolfi-base"
user dev
EOF

  source lib/toml.sh
  run parse_toml "$TESTDIR/config.toml"

  [ "$status" -eq 1 ]
  [[ "$output" == *"line 3"* ]]
}

@test "handles single-element arrays" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[container]
packages = ["git"]
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_CONTAINER_PACKAGES" = "git" ]
}

@test "handles empty arrays" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[mounts]
extra = []
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_MOUNTS_EXTRA" = "" ]
}

@test "handles dotted section headers" {
  cat > "$TESTDIR/config.toml" << 'EOF'
[container.network]
mode = "bridge"
EOF

  source lib/toml.sh
  parse_toml "$TESTDIR/config.toml"

  [ "$CONFIG_CONTAINER_NETWORK_MODE" = "bridge" ]
}
