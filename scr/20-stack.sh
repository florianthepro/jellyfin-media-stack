#!/usr/bin/env bash

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    fail "/etc/os-release nicht gefunden. Dieses Skript unterstützt Debian und Ubuntu." 
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian|ubuntu) ;;
    *) fail "Nur Debian/Ubuntu werden unterstützt. Gefunden: ${ID:-unbekannt}" ;;
  esac

  info "Betriebssystem erkannt: ${PRETTY_NAME:-${ID:-unbekannt}}"
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    info "Docker ist bereits installiert."
    return 0
  fi

  if ask_yes "Docker installieren?" y; then
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg lsb-release uidmap
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(. /etc/os-release; echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  else
    fail "Docker ist erforderlich, damit der Stack starten kann."
  fi
}

detect_media_dir() {
  load_env_if_available
  if [[ -n "${MEDIA:-}" ]]; then
    MEDIA_DIR="$MEDIA"
  else
    MEDIA_DIR="$MEDIA_DEFAULT"
  fi

  if [[ -n "${MEDIA_DIR:-}" ]]; then
    MEDIA_DIR="$(trim "$MEDIA_DIR")"
  fi

  if [[ -z "${MEDIA_DIR:-}" ]]; then
    MEDIA_DIR="$(read_value "Medien-Verzeichnis" "$MEDIA_DEFAULT")"
  fi

  if [[ "$MEDIA_DIR" != /* ]]; then
    fail "Das Medien-Verzeichnis muss ein absoluter Pfad sein: $MEDIA_DIR"
  fi

  export MEDIA="$MEDIA_DIR"
  info "Media-Verzeichnis: $MEDIA"
}

prepare_directories() {
  install -d -m 0755 "$INSTALL_DIR"
  install -d -m 0755 "$DATA_DIR"
  install -d -m 0775 "$MEDIA" "$MEDIA/movies" "$MEDIA/series" "$MEDIA/downloads" 2>/dev/null || true
  for service in jellyfin seerr sonarr radarr prowlarr qbittorrent tailscale; do
    install -d -m 0775 "$DATA_DIR/$service" 2>/dev/null || true
  done
}

start_stack() {
  cd "$INSTALL_DIR"
  docker compose up -d --remove-orphans
  docker compose ps
}
