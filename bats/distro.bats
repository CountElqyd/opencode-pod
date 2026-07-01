#!/usr/bin/env bats

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TESTDIR"
}

@test "detects Arch Linux" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=arch
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [ "$DISTRO_ID" = "arch" ]
  [[ "$DISTRO_INSTALL_CMD" == *"pacman"* ]]
}

@test "detects Fedora" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=fedora
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [ "$DISTRO_ID" = "fedora" ]
  [[ "$DISTRO_INSTALL_CMD" == *"dnf"* ]]
}

@test "detects Ubuntu" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=ubuntu
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [ "$DISTRO_ID" = "ubuntu" ]
  [[ "$DISTRO_INSTALL_CMD" == *"apt"* ]]
}

@test "detects Debian" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=debian
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [ "$DISTRO_ID" = "debian" ]
  [[ "$DISTRO_INSTALL_CMD" == *"apt"* ]]
}

@test "handles unknown distro" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=nixos
EOF

  source lib/distro.sh
  run detect_distro "$TESTDIR/os-release"
  [ "$status" -eq 0 ]
  [ "$DISTRO_ID" = "unknown" ]
  [[ "$DISTRO_INSTALL_CMD" == *"https://podman.io"* ]]
}

@test "handles missing os-release file" {
  source lib/distro.sh
  run detect_distro "$TESTDIR/nonexistent"
  [ "$status" -eq 1 ]
}

@test "sets subuid instructions for Arch" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=arch
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [[ "$DISTRO_SUBUID_INSTRUCTIONS" == *"/etc/subuid"* ]]
  [[ "$DISTRO_SUBUID_INSTRUCTIONS" == *"usermod"* ]]
}

@test "subuid auto for Fedora" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=fedora
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [[ "$DISTRO_SUBUID_SETUP" == "auto" ]]
}

@test "subuid auto for Ubuntu" {
  cat > "$TESTDIR/os-release" << 'EOF'
ID=ubuntu
EOF

  source lib/distro.sh
  detect_distro "$TESTDIR/os-release"
  [[ "$DISTRO_SUBUID_SETUP" == "auto" ]]
}
