#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT_DIR
export SCRIPT_DIR="$ROOT_DIR/scr"

SETUP_MODE="${SETUP_MODE:-w}"
APP_NAME="jellyfin-media-stack"
INSTALL_DIR="${INSTALL_DIR:-/opt/${APP_NAME}}"
MEDIA_DEFAULT="${MEDIA_DEFAULT:-/srv/media}"
DATA_DIR="${DATA_DIR:-$INSTALL_DIR/data}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
QBIT_USER="${QBIT_USER:-admin}"
QBIT_PORT="${QBIT_PORT:-8080}"
QBIT_TORRENT_PORT="${QBIT_TORRENT_PORT:-6881}"
TS_HOST="${TS_HOST:-jellystack}"
AUTO_MODE="0"
SUDO_USER="${SUDO_USER:-$(id -un 2>/dev/null || echo root)}"

for script in "$SCRIPT_DIR"/*.sh; do
  [[ -f "$script" ]] && source "$script"
done

main() {
  ensure_root
  choose_mode
  detect_os
  detect_media_dir
  ensure_docker
  generate_credentials
  write_env_file
  write_compose_file
  prepare_directories
  start_stack
  apply_runtime_auth
  print_summary
}

main "$@"
