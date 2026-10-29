#!/usr/bin/env bash

write_env_file() {
  local env_file="$INSTALL_DIR/.env"
  if [[ ! -d "$INSTALL_DIR" ]]; then install -d -m 0755 "$INSTALL_DIR"; fi

  cat >"$env_file" <<ENV
TZ=$TIMEZONE
PUID=1000
PGID=1000
DATA=$DATA_DIR
MEDIA=$MEDIA
QBIT_USER=$QBIT_USER
QBIT_PASSWORD=$QBIT_PASSWORD
QBIT_API_KEY=$QBIT_API_KEY
QBIT_PORT=$QBIT_PORT
QBIT_TORRENT_PORT=$QBIT_TORRENT_PORT
TS_HOST=$TS_HOST
TS_KEY=${TS_KEY:-}
JELLYFIN_USER=admin
JELLYFIN_PASSWORD=$JELLYFIN_PASSWORD
SONARR_USER=admin
SONARR_PASSWORD=$SONARR_PASSWORD
RADARR_USER=admin
RADARR_PASSWORD=$RADARR_PASSWORD
PROWLARR_USER=admin
PROWLARR_PASSWORD=$PROWLARR_PASSWORD
SEERR_USER=admin
SEERR_PASSWORD=$SEERR_PASSWORD
ENV

  chmod 600 "$env_file"
  info "Umgebungsdatei erstellt: $env_file"
}

write_compose_file() {
  cp "$ROOT_DIR/compose.yaml" "$INSTALL_DIR/compose.yaml"
  info "Compose-Datei kopiert nach $INSTALL_DIR/compose.yaml"
}

generate_credentials() {
  if [[ -z "${QBIT_PASSWORD:-}" ]]; then
    QBIT_PASSWORD="$(generate_password)"
  fi
  if [[ -z "${QBIT_API_KEY:-}" ]]; then
    QBIT_API_KEY="$(generate_password)"
  fi
  if [[ -z "${JELLYFIN_PASSWORD:-}" ]]; then
    JELLYFIN_PASSWORD="$(generate_password)"
  fi
  if [[ -z "${SONARR_PASSWORD:-}" ]]; then
    SONARR_PASSWORD="$(generate_password)"
  fi
  if [[ -z "${RADARR_PASSWORD:-}" ]]; then
    RADARR_PASSWORD="$(generate_password)"
  fi
  if [[ -z "${PROWLARR_PASSWORD:-}" ]]; then
    PROWLARR_PASSWORD="$(generate_password)"
  fi
  if [[ -z "${SEERR_PASSWORD:-}" ]]; then
    SEERR_PASSWORD="$(generate_password)"
  fi

  export QBIT_PASSWORD QBIT_API_KEY JELLYFIN_PASSWORD SONARR_PASSWORD RADARR_PASSWORD PROWLARR_PASSWORD SEERR_PASSWORD
  info "Zugangsdaten erzeugt."
}

apply_runtime_auth() {
  local qbit_host="http://127.0.0.1:${QBIT_PORT:-8080}"
  local qbit_url="${qbit_host}/api/v2/auth/login"
  local max_wait=60

  if ! docker ps --format '{{.Names}}' | grep -qx 'qbittorrent'; then
    info "qBittorrent container läuft noch nicht. Überspringe API-Setup."
    return 0
  fi

  local attempt=0
  while (( attempt < max_wait )); do
    if curl -fsSL -u "${QBIT_USER:-admin}:${QBIT_PASSWORD}" "$qbit_url" >/tmp/qbit-login.$$ 2>/dev/null; then
      break
    fi
    sleep 2
    attempt=$((attempt + 1))
  done

  if (( attempt >= max_wait )); then
    warn "qBittorrent-Login konnte nicht automatisch verifiziert werden. Bitte Web-UI später prüfen."
    return 0
  fi

  if ! curl -fsSL -u "${QBIT_USER:-admin}:${QBIT_PASSWORD}" "${qbit_host}/api/v2/app/preferences" >/tmp/qbit-pref.$$ 2>/dev/null; then
    warn "qBittorrent API nicht erreichbar. Das ist normal, wenn der Web-UI initial nicht fertig konfiguriert ist."
    return 0
  fi

  printf '%s\n' "$QBIT_API_KEY" > "$INSTALL_DIR/qbit_api_key.txt"
  info "qBittorrent-API-Key wurde in $INSTALL_DIR/qbit_api_key.txt gespeichert."
}
