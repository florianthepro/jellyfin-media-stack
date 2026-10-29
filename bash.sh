#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="jellyfin-media-stack"
INSTALL_DIR="${INSTALL_DIR:-/opt/${APP_NAME}}"
MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
AUTO_MODE=0

if [[ "${1:-}" == "--auto" ]]; then
  AUTO_MODE=1
fi

info(){ printf '\033[1;34m[i]\033[0m %s\n' "$1"; }
ok(){ printf '\033[1;32m[✓]\033[0m %s\n' "$1"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$1" >&2; }
fail(){ printf '\033[1;31m[✗]\033[0m %s\n' "$1" >&2; exit 1; }

random_password(){
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 25
}

ask_yes(){
  local prompt="$1" default="${2:-n}"
  local answer=""
  if [[ "$AUTO_MODE" -eq 1 ]]; then
    return 0
  fi
  printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  IFS= read -r answer </dev/tty || answer="$default"
  answer="${answer:-$default}"
  case "${answer,,}" in
    y|yes|j|ja) return 0 ;;
    n|no|nein) return 1 ;;
    *) return 1 ;;
  esac
}

require_root(){
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Bitte mit sudo ausführen: curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/bash.sh | sudo bash"
}

detect_os(){
  [[ -r /etc/os-release ]] || fail "/etc/os-release fehlt. Debian/Ubuntu wird benötigt."
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) fail "Betriebssystem ${ID:-unbekannt} nicht unterstützt. Nutze Debian oder Ubuntu." ;;
  esac
}

check_existing_install(){
  if [[ -f "$INSTALL_DIR/compose.yaml" ]] || [[ -f "$INSTALL_DIR/.env" ]]; then
    if [[ "$AUTO_MODE" -eq 1 ]]; then
      info "Vorhandene Installation erkannt. Überschreibe sie automatisch."
      rm -rf "$INSTALL_DIR"
      return 0
    fi

    if ask_yes "Vorhandene Installation erkannt. Neu aufsetzen?" n; then
      rm -rf "$INSTALL_DIR"
      return 0
    fi
    info "Bestehende Installation bleibt unverändert."
    exit 0
  fi
}

install_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker/Compose vorhanden"
    return 0
  fi

  if [[ "$AUTO_MODE" -eq 1 ]]; then
    info "Docker wird installiert..."
  else
    warn "Docker fehlt. Installation wird gestartet..."
  fi

  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  . /etc/os-release
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker compose version >/dev/null 2>&1 || fail "Docker Compose konnte nicht initialisiert werden."
  ok "Docker installiert"
}

choose_media_dir(){
  if [[ -d "$MEDIA_DIR" ]]; then
    return 0
  fi

  if [[ "$AUTO_MODE" -eq 1 ]]; then
    install -d -m 0775 "$MEDIA_DIR" "$MEDIA_DIR/movies" "$MEDIA_DIR/series" "$MEDIA_DIR/downloads"
    return 0
  fi

  printf 'Medienpfad [%s]: ' "$MEDIA_DIR" >/dev/tty
  IFS= read -r MEDIA_DIR </dev/tty || MEDIA_DIR="/srv/media"
  MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
  [[ "$MEDIA_DIR" == /* ]] || fail "Medienpfad muss absolut sein: $MEDIA_DIR"
  install -d -m 0775 "$MEDIA_DIR" "$MEDIA_DIR/movies" "$MEDIA_DIR/series" "$MEDIA_DIR/downloads"
}

write_env_file(){
  local qbit_user="admin"
  local qbit_password
  local qbit_api_key
  local app_password
  local jellyfin_password
  local sonarr_password
  local radarr_password
  local prowlarr_password
  local seerr_password

  qbit_password="$(random_password)"
  qbit_api_key="$(random_password)"
  app_password="$(random_password)"
  jellyfin_password="$(random_password)"
  sonarr_password="$(random_password)"
  radarr_password="$(random_password)"
  prowlarr_password="$(random_password)"
  seerr_password="$(random_password)"

  mkdir -p "$INSTALL_DIR"
  cat > "$INSTALL_DIR/.env" <<EOF
TZ=$TIMEZONE
PUID=1000
PGID=1000
DATA=$INSTALL_DIR/data
MEDIA=$MEDIA_DIR
QBIT_USER=$qbit_user
QBIT_PASSWORD=$qbit_password
QBIT_API_KEY=$qbit_api_key
QBIT_PORT=8080
QBIT_TORRENT_PORT=6881
TS_HOST=jellystack
TS_KEY=
JELLYFIN_USER=admin
JELLYFIN_PASSWORD=$jellyfin_password
SONARR_USER=admin
SONARR_PASSWORD=$sonarr_password
RADARR_USER=admin
RADARR_PASSWORD=$radarr_password
PROWLARR_USER=admin
PROWLARR_PASSWORD=$prowlarr_password
SEERR_USER=admin
SEERR_PASSWORD=$seerr_password
APP_PASSWORD=$app_password
EOF
  chmod 600 "$INSTALL_DIR/.env"

  printf '%s\n' "$qbit_password" > "$INSTALL_DIR/qbit_web_password.txt"
  printf '%s\n' "$qbit_api_key" > "$INSTALL_DIR/qbit_api_key.txt"
  printf '%s\n' "$app_password" > "$INSTALL_DIR/app_password.txt"
}

write_compose_file(){
  cat > "$INSTALL_DIR/compose.yaml" <<'YAML'
name: jellyfin-media-stack
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    environment:
      TZ: ${TZ:-Europe/Berlin}
    ports:
      - "8096:8096"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/jellyfin/config:/config"
      - "${DATA:-/opt/jellyfin-media-stack/data}/jellyfin/cache:/cache"
      - "${MEDIA:-/srv/media}/movies:/media/movies:ro"
      - "${MEDIA:-/srv/media}/series:/media/series:ro"
    restart: unless-stopped

  seerr:
    image: ghcr.io/seerr-team/seerr:latest
    container_name: seerr
    environment:
      TZ: ${TZ:-Europe/Berlin}
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
    ports:
      - "5055:5055"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/seerr/config:/app/config"
    restart: unless-stopped

  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: sonarr
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-Europe/Berlin}
    ports:
      - "8989:8989"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/sonarr/config:/config"
      - "${MEDIA:-/srv/media}/series:/tv"
      - "${MEDIA:-/srv/media}/downloads:/downloads"
    restart: unless-stopped

  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: radarr
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-Europe/Berlin}
    ports:
      - "7878:7878"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/radarr/config:/config"
      - "${MEDIA:-/srv/media}/movies:/movies"
      - "${MEDIA:-/srv/media}/downloads:/downloads"
    restart: unless-stopped

  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: prowlarr
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-Europe/Berlin}
    ports:
      - "9696:9696"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/prowlarr/config:/config"
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-Europe/Berlin}
      WEBUI_PORT: ${QBIT_PORT:-8080}
      TORRENTING_PORT: ${QBIT_TORRENT_PORT:-6881}
      WEBUI_USERNAME: ${QBIT_USER:-admin}
      WEBUI_PASSWORD: ${QBIT_PASSWORD:-change-me}
    ports:
      - "${QBIT_PORT:-8080}:8080"
      - "${QBIT_TORRENT_PORT:-6881}:6881/tcp"
      - "${QBIT_TORRENT_PORT:-6881}:6881/udp"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/qbittorrent/config:/config"
      - "${MEDIA:-/srv/media}/downloads:/downloads"
    restart: unless-stopped

  tailscale:
    profiles: ["tailscale"]
    image: tailscale/tailscale:stable
    container_name: tailscale
    hostname: ${TS_HOST:-jellystack}
    environment:
      TS_AUTHKEY: ${TS_KEY:-}
      TS_AUTH_ONCE: "true"
      TS_HOSTNAME: ${TS_HOST:-jellystack}
      TS_STATE_DIR: /var/lib/tailscale
      TS_USERSPACE: "false"
    volumes:
      - "${DATA:-/opt/jellyfin-media-stack/data}/tailscale/state:/var/lib/tailscale"
      - "/dev/net/tun:/dev/net/tun"
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped

  mullvad:
    profiles: ["vpn"]
    image: ghcr.io/mullvad/mullvadvpn:latest
    container_name: mullvad
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    network_mode: service:qbittorrent
    depends_on:
      - qbittorrent
    restart: unless-stopped
YAML

  set -a
  . "$INSTALL_DIR/.env"
  set +a
}

start_stack(){
  cd "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/data"/jellyfin/config "$INSTALL_DIR/data"/jellyfin/cache "$INSTALL_DIR/data"/seerr/config "$INSTALL_DIR/data"/sonarr/config "$INSTALL_DIR/data"/radarr/config "$INSTALL_DIR/data"/prowlarr/config "$INSTALL_DIR/data"/qbittorrent/config "$INSTALL_DIR/data"/tailscale/state
  docker compose up -d --remove-orphans
}

print_summary(){
  local qbit_api
  local qbit_password
  local app_password

  qbit_api="$(cat "$INSTALL_DIR/qbit_api_key.txt" 2>/dev/null || echo unknown)"
  qbit_password="$(cat "$INSTALL_DIR/qbit_web_password.txt" 2>/dev/null || echo unknown)"
  app_password="$(cat "$INSTALL_DIR/app_password.txt" 2>/dev/null || echo unknown)"

  printf '\n====================================================\n'
  printf 'Jellyfin Media Stack\n'
  printf '====================================================\n'
  printf 'Admin Benutzer: admin\n'
  printf 'Admin Passwort: %s\n' "$app_password"
  printf 'qBittorrent Benutzer: admin\n'
  printf 'qBittorrent Passwort: %s\n' "$qbit_password"
  printf 'qBittorrent API-Key: %s\n' "$qbit_api"
  printf '\nURLs\n'
  printf '  Jellyfin: http://127.0.0.1:8096\n'
  printf '  Sonarr:   http://127.0.0.1:8989\n'
  printf '  Radarr:   http://127.0.0.1:7878\n'
  printf '  Prowlarr: http://127.0.0.1:9696\n'
  printf '  Seerr:    http://127.0.0.1:5055\n'
  printf '  qBittorrent: http://127.0.0.1:8080\n'
  printf '  Downloadpfad: %s\n' "$MEDIA_DIR/downloads"
  printf '  Installationsordner: %s\n' "$INSTALL_DIR"
  printf '  Optional VPN: docker compose --profile vpn up -d\n'
  printf '====================================================\n\n'
}

main(){
  require_root
  detect_os
  check_existing_install
  install_docker
  choose_media_dir
  write_env_file
  write_compose_file
  start_stack
  print_summary
}

main "$@"
