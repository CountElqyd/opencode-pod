#!/usr/bin/env bash
# OS/distro detection from /etc/os-release.
# Sets DISTRO_ID, DISTRO_INSTALL_CMD, DISTRO_SUBUID_SETUP, DISTRO_SUBUID_INSTRUCTIONS.

detect_distro() {
  local os_release="${1:-/etc/os-release}"

  if [[ ! -f "$os_release" ]]; then
    echo "Error: cannot detect OS — $os_release not found" >&2
    return 1
  fi

  local id=""
  while IFS='=' read -r key value; do
    case "$key" in
      ID) id="${value//\"/}"; id="${id//\'/}"; break ;; 
    esac
  done < "$os_release"

  DISTRO_ID="${id:-unknown}"

  case "$DISTRO_ID" in
    arch)
      DISTRO_INSTALL_CMD="sudo pacman -S podman slirp4netns fuse-overlayfs"
      DISTRO_SUBUID_SETUP="manual"
      DISTRO_SUBUID_INSTRUCTIONS=$'Add your user to /etc/subuid and /etc/subgid:\n  echo "$(whoami):100000:65536" | sudo tee -a /etc/subuid\n  echo "$(whoami):100000:65536" | sudo tee -a /etc/subgid\n  usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(whoami)'
      ;;
    fedora)
      DISTRO_INSTALL_CMD="sudo dnf install -y podman"
      DISTRO_SUBUID_SETUP="auto"
      DISTRO_SUBUID_INSTRUCTIONS="Fedora configures subuid/subgid automatically."
      ;;
    ubuntu|debian)
      DISTRO_INSTALL_CMD="sudo apt install -y podman"
      DISTRO_SUBUID_SETUP="auto"
      DISTRO_SUBUID_INSTRUCTIONS="Ubuntu/Debian configures subuid/subgid automatically (10+)."
      ;;
    *)
      DISTRO_ID="unknown"
      DISTRO_INSTALL_CMD="See https://podman.io/docs/installation for your distribution"
      DISTRO_SUBUID_SETUP="manual"
      DISTRO_SUBUID_INSTRUCTIONS="See https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md"
      ;;
  esac

  export DISTRO_ID DISTRO_INSTALL_CMD DISTRO_SUBUID_SETUP DISTRO_SUBUID_INSTRUCTIONS
  return 0
}
