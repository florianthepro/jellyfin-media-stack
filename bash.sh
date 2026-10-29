#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="jellyfin-media-stack"
INSTALL_DIR="${INSTALL_DIR:-/opt/${APP_NAME}}"
MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
TIMEZONE="${TIMEZONE:-Europe/Berlin}"
AUTO_MODE=0

info(){ printf '\033[1;34m[i]\033[0m %s\n' "$1"; }
ok(){ printf '\033[1;32m[✓]\033[0m %s\n' "$1"; }
warn(){ printf '\033[1;33m[!]\033[0m %s\n' "$1" >&2; }
fail(){ printf '\033[1;31m[✗]\033[0m %s\n' "$1" >&2; exit 1; }
random_password(){ LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 25; }

require_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || fail "Bitte mit sudo ausführen."; }

check_os(){
  [[ -r /etc/os-release ]] || fail "/etc/os-release fehlt."
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) fail "Nur Debian/Ubuntu werden unterstützt." ;;
  esac
}

ask_yes(){
  local prompt="$1" default="${2:-n}"
  local answer
  printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  IFS= read -r answer </dev/tty || answer="$default"
  answer="${answer:-$default}"
  case "${answer,,}" in
    y|yes|j|ja) return 0 ;;
    *) return 1 ;;
  esac
}

install_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "Docker/Compose vorhanden"
    return 0
  fi
  warn "Docker fehlt. Installation wird gestartet..."
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
    ok "Medienpfad: $MEDIA_DIR"
    return 0
  fi
  if [[ -t 0 ]]; then
    printf 'Medienpfad [%s]: ' "$MEDIA_DIR" >/dev/tty
    IFS= read -r MEDIA_DIR </dev/tty || MEDIA_DIR="/srv/media"
  fi
  MEDIA_DIR="${MEDIA_DIR:-/srv/media}"
  [[ "$MEDIA_DIR" == /* ]] || fail "Medienpfad muss absolut sein: $MEDIA_DIR"
  install -d -m 0775 "$MEDIA_DIR" "$MEDIA_DIR/movies" "$MEDIA_DIR/series" "$MEDIA_DIR/downloads"
  ok "Medienpfad: $MEDIA_DIR"
}

detect_existing(){
  if [[ -f "$INSTALL_DIR/.env" ]] || [[ -f "$INSTALL_DIR/compose.yaml" ]]; then
    if [[ -t 0 ]] && ask_yes "Vorhandene Installation erkannt. Neu aufsetzen?" n; then
      rm -rf "$INSTALL_DIR"
      return
    fi
    if [[ ! -t 0 ]]; then
      rm -rf "$INSTALL_DIR"
      return
    fi
    info "Bestehende Installation bleibt unverändert."
    exit 0
  fi
}

generate_credentials(){
  APP_PASSWORD="$(random_password)"
  QBIT_PASSWORD="$(random_password)"
  QBIT_API_KEY="$(random_password)"
  JELLYFIN_PASSWORD="$(random_password)"
  SONARR_PASSWORD="$(random_password)"
  RADARR_PASSWORD="$(random_password)"
  PROWLARR_PASSWORD="$(random_password)"
  SEERR_PASSWORD="$(random_password)"
}

write_env(){
  mkdir -p "$INSTALL_DIR"
  cat > "$INSTALL_DIR/.env" <<EOF
TZ=$TIMEZONE
PUID=1000
PGID=1000
DATA=$INSTALL_DIR/data
MEDIA=$MEDIA_DIR
QBIT_USER=admin
QBIT_PASSWORD=$QBIT_PASSWORD
QBIT_API_KEY=$QBIT_API_KEY
QBIT_PORT=8080
QBIT_TORRENT_PORT=6881
TS_HOST=jellystack
TS_KEY=
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
APP_PASSWORD=$APP_PASSWORD
EOF
  chmod 600 "$INSTALL_DIR/.env"
  printf '%s\n' "$QBIT_PASSWORD" > "$INSTALL_DIR/qbit_web_password.txt"
  printf '%s\n' "$QBIT_API_KEY" > "$INSTALL_DIR/qbit_api_key.txt"
  printf '%s\n' "$APP_PASSWORD" > "$INSTALL_DIR/app_password.txt"
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
}

start_stack(){
  cd "$INSTALL_DIR"
  mkdir -p "$INSTALL_DIR/data" "$INSTALL_DIR/data"/jellyfin/config "$INSTALL_DIR/data"/jellyfin/cache "$INSTALL_DIR/data"/seerr/config "$INSTALL_DIR/data"/sonarr/config "$INSTALL_DIR/data"/radarr/config "$INSTALL_DIR/data"/prowlarr/config "$INSTALL_DIR/data"/qbittorrent/config "$INSTALL_DIR/data"/tailscale/state
  docker compose up -d --remove-orphans
}

print_summary(){
  printf '\n====================================================\n'
  printf 'Jellyfin Media Stack\n'
  printf '====================================================\n'
  printf 'Admin Benutzer: admin\n'
  printf 'Admin Passwort: %s\n' "$APP_PASSWORD"
  printf 'qBittorrent Benutzer: admin\n'
  printf 'qBittorrent Passwort: %s\n' "$QBIT_PASSWORD"
  printf 'qBittorrent API-Key: %s\n' "$QBIT_API_KEY"
  printf '\nURLs\n'
  printf '  Jellyfin: http://127.0.0.1:8096\n'
  printf '  Sonarr:   http://127.0.0.1:8989\n'
  printf '  Radarr:   http://127.0.0.1:7878\n'
  printf '  Prowlarr: http://127.0.0.1:9696\n'
  printf '  Seerr:    http://127.0.0.1:5055\n'
  printf '  qBittorrent: http://127.0.0.1:8080\n'
  printf '  Downloadpfad: %s/downloads\n' "$MEDIA_DIR"
  printf '  Installationsordner: %s\n' "$INSTALL_DIR"
  printf '  Optional VPN: docker compose --profile vpn up -d\n'
  printf '====================================================\n'
}

main(){
  require_root
  check_os
  detect_existing
  install_docker
  choose_media_dir
  generate_credentials
  write_env
  write_compose
  start_stack
  print_summary
}

main "$@"
