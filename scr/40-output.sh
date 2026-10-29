#!/usr/bin/env bash

print_summary() {
  local safe_pw="${QBIT_PASSWORD:-<nicht gesetzt>}"
  local api_key="${QBIT_API_KEY:-<nicht gesetzt>}"

  printf '\n====================================================\n'
  printf 'Jellyfin Media Stack wurde initialisiert\n'
  printf '====================================================\n'
  printf 'Admin-Benutzer: admin\n'
  printf 'Admin-Passwort: %s\n' "$safe_pw"
  printf 'qBittorrent API-Key: %s\n' "$api_key"
  printf '\nURLs:\n'
  printf '  Jellyfin: http://127.0.0.1:8096\n'
  printf '  Seerr:    http://127.0.0.1:5055\n'
  printf '  Sonarr:   http://127.0.0.1:8989\n'
  printf '  Radarr:   http://127.0.0.1:7878\n'
  printf '  Prowlarr: http://127.0.0.1:9696\n'
  printf '  qBittorrent: http://127.0.0.1:%s\n' "$QBIT_PORT"
  printf '\nDatenverzeichnis:\n'
  printf '  MEDIA: %s\n' "$MEDIA"
  printf '  DATA:  %s\n' "$DATA_DIR"
  printf '  LOGS:  %s\n' "$INSTALL_DIR"
  printf '\nWichtige Hinweise:\n'
  printf '  - Das Projekt nutzt standardmäßig admin/admin für die Erstkonfiguration, aber das Bild wird mit dem erzeugten zufälligen Passwort konfiguriert.\n'
  printf '  - qBittorrent befindet sich unter %s.\n' "http://127.0.0.1:${QBIT_PORT}"
  printf '  - Das API-Token liegt in %s/qbit_api_key.txt\n' "$INSTALL_DIR"
  printf '  - Für Mullvad: docker compose --profile vpn up -d\n'
  printf '====================================================\n\n'
}
