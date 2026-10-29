#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="jellyfin-media-stack"
INSTALL_DIR="${INSTALL_DIR:-/opt/${APP_NAME}}"
MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
MODE="${MODE:-w}"
ADMIN_USER="${ADMIN_USER:-admin}"
QBIT_USER="${QBIT_USER:-admin}"
QBIT_PORT="${QBIT_PORT:-8080}"
QBIT_TORRENT_PORT="${QBIT_TORRENT_PORT:-6881}"
TS_HOST="${TS_HOST:-jellystack}"
LOG_FILE="/var/log/${APP_NAME}.log"

info(){ printf '\033[1;34m[i]\033[0m %s\n' "$1"; }
ok(){ printf '\033[1;32m[✓]\033[0m %s\n' "$1"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$1" >&2; }
fail(){ printf '\033[1;31m[✗]\033[0m %s\n' "$1" >&2; exit 1; }

random_string(){
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 25
}

read_choice(){
  local prompt="$1" default="$2"
  local answer
  if [[ -t 0 ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
    IFS= read -r answer </dev/tty || answer="$default"
    printf '%s' "${answer:-$default}"
  else
    printf '%s' "$default"
  fi
}

ensure_root(){
  [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Bitte mit sudo ausführen: curl -fsSL ... | sudo bash"
}

detect_os(){
  [[ -r /etc/os-release ]] || fail "/etc/os-release fehlt. Nur Debian/Ubuntu unterstützt."
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) fail "Betriebssystem ${ID:-unbekannt} wird nicht unterstützt. Nutze Debian oder Ubuntu." ;;
  esac
}

ensure_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker gefunden"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    fail "Docker fehlt und kann nicht automatisch installiert werden, weil kein interaktives Terminal vorhanden ist."
  fi

  warn "Docker wird installiert..."
  apt-get update -qq
  apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker compose version >/dev/null 2>&1 || fail "Docker Compose konnte nicht initialisiert werden."
  ok "Docker installiert"
}

choose_mode(){
  case "${MODE,,}" in
    w|wizard|interactive) MODE="w" ;;
    a|auto|automatic) MODE="a" ;;
    m|manual) MODE="m" ;;
    *) MODE="w" ;;
  esac

  if [[ "$MODE" == "w" && -t 0 ]]; then
    local answer
    printf 'Setup-Modus [w=Wizard, a=automatisch, m=manuell]: ' >/dev/tty
    IFS= read -r answer </dev/tty || answer="w"
    case "${answer,,}" in
      a|auto|automatic) MODE="a" ;;
      m|manual) MODE="m" ;;
      *) MODE="w" ;;
    esac
  fi
}

prepare_install_dir(){
  install -d -m 0755 "$INSTALL_DIR"
  install -m 0600 /dev/null "$LOG_FILE" 2>/dev/null || true
}

detect_media(){
  if [[ -n "${MEDIA_DIR:-}" && "$MEDIA_DIR" != "" ]]; then
    :
  elif [[ -t 0 ]]; then
    MEDIA_DIR="$(read_choice "Medienpfad" "/srv/media")"
  else
    MEDIA_DIR="/srv/media"
  fi

  [[ "$MEDIA_DIR" == /* ]] || fail "Medienpfad muss absolut sein: $MEDIA_DIR"
  install -d -m 0775 "$MEDIA_DIR" "$MEDIA_DIR/movies" "$MEDIA_DIR/series" "$MEDIA_DIR/downloads" 2>/dev/null || true
  ok "Medienpfad: $MEDIA_DIR"
}

write_env(){
  local APP_PASSWORD
  local QBIT_PASSWORD
  local QBIT_API_KEY
  local JELLYFIN_PASSWORD
  local SONARR_PASSWORD
  local RADARR_PASSWORD
  local PROWLARR_PASSWORD
  local SEERR_PASSWORD

  APP_PASSWORD="$(random_string)"
  QBIT_PASSWORD="$(random_string)"
  QBIT_API_KEY="$(random_string)"
  JELLYFIN_PASSWORD="$(random_string)"
  SONARR_PASSWORD="$(random_string)"
  RADARR_PASSWORD="$(random_string)"
  PROWLARR_PASSWORD="$(random_string)"
  SEERR_PASSWORD="$(random_string)"

  cat > "$INSTALL_DIR/.env" <<EOF
TZ=$TIMEZONE
PUID=1000
PGID=1000
DATA=$INSTALL_DIR/data
MEDIA=$MEDIA_DIR
QBIT_USER=$QBIT_USER
QBIT_PASSWORD=$QBIT_PASSWORD
QBIT_API_KEY=$QBIT_API_KEY
QBIT_PORT=$QBIT_PORT
QBIT_TORRENT_PORT=$QBIT_TORRENT_PORT
TS_HOST=$TS_HOST
TS_KEY=
JELLYFIN_USER=$ADMIN_USER
JELLYFIN_PASSWORD=$JELLYFIN_PASSWORD
SONARR_USER=$ADMIN_USER
SONARR_PASSWORD=$SONARR_PASSWORD
RADARR_USER=$ADMIN_USER
RADARR_PASSWORD=$RADARR_PASSWORD
PROWLARR_USER=$ADMIN_USER
PROWLARR_PASSWORD=$PROWLARR_PASSWORD
SEERR_USER=$ADMIN_USER
SEERR_PASSWORD=$SEERR_PASSWORD
APP_PASSWORD=$APP_PASSWORD
EOF

  chmod 600 "$INSTALL_DIR/.env"
  printf '%s\n' "$QBIT_API_KEY" > "$INSTALL_DIR/qbit_api_key.txt"
  printf '%s\n' "$QBIT_PASSWORD" > "$INSTALL_DIR/qbit_web_password.txt"
  printf '%s\n' "$APP_PASSWORD" > "$INSTALL_DIR/app_password.txt"

  export QBIT_PASSWORD QBIT_API_KEY JELLYFIN_PASSWORD SONARR_PASSWORD RADARR_PASSWORD PROWLARR_PASSWORD SEERR_PASSWORD APP_PASSWORD
}

write_compose(){
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
  install -d -m 0775 "$DATA_DIR" 2>/dev/null || true
  for dir in "$INSTALL_DIR/data"/jellyfin "$INSTALL_DIR/data"/seerr "$INSTALL_DIR/data"/sonarr "$INSTALL_DIR/data"/radarr "$INSTALL_DIR/data"/prowlarr "$INSTALL_DIR/data"/qbittorrent "$INSTALL_DIR/data"/tailscale; do
    install -d -m 0775 "$dir" 2>/dev/null || true
  done
  docker compose up -d --remove-orphans
}

print_summary(){
  printf '\n====================================================\n'
  printf 'Jellyfin Media Stack installiert\n'
  printf '====================================================\n'
  printf 'Admin Benutzer: %s\n' "$ADMIN_USER"
  printf 'Admin Passwort: %s\n' "${APP_PASSWORD:-$(cat "$INSTALL_DIR/app_password.txt" 2>/dev/null || echo unknown)}"
  printf 'qBittorrent Web: http://127.0.0.1:%s\n' "$QBIT_PORT"
  printf 'Jellyfin: http://127.0.0.1:8096\n'
  printf 'Sonarr: http://127.0.0.1:8989\n'
  printf 'Radarr: http://127.0.0.1:7878\n'
  printf 'Prowlarr: http://127.0.0.1:9696\n'
  printf 'Seerr: http://127.0.0.1:5055\n'
  printf 'qBittorrent API-Key: %s\n' "$(cat "$INSTALL_DIR/qbit_api_key.txt" 2>/dev/null || echo unknown)"
  printf 'Medienpfad: %s\n' "$MEDIA_DIR"
  printf 'Installationspfad: %s\n' "$INSTALL_DIR"
  printf 'Optional VPN: docker compose --profile vpn up -d\n'
  printf '====================================================\n'
}

main(){
  ensure_root
  detect_os
  choose_mode
  prepare_install_dir
  detect_media
  ensure_docker
  write_env
  write_compose
  start_stack
  print_summary
}

main "$@"
