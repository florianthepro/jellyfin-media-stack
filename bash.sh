#!/usr/bin/env bash
set -Eeuo pipefail

RAW_URL="https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/a.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "$RAW_URL" -o "$TMP_DIR/a.sh" || {
  echo "Fehler beim Laden von a.sh" >&2
  exit 1
}
chmod +x "$TMP_DIR/a.sh"
exec bash "$TMP_DIR/a.sh" "$@"
