(# Setup Jellyfin Media Stack)[https://123.com](test)

## command
```
cd ~ && sudo nano setup-jfms.sh && sudo chmod + x .\setup-jfms.sh && sudo setup-jfms.sh
```
enter [### input](input) from the bottom than follow commands below
```
cd ~ && sudo rm setup-jfms.sh
```

### input
```
#!/usr/bin/env bash
set -Eeuo pipefail

clear

NAME="jellyfin-media-stack"
DEFAULT_ROOT="/opt/jfms"
COMPOSE_SERVICE_ALWAYS="cloudflared"

section() {
    printf '\n\033[1;36m%s\033[0m\n' "=== $1 ==="
}

ok() {
    printf '\033[1;32mOK:\033[0m %s\n' "$1"
}

info() {
    printf '\033[1;34mINFO:\033[0m %s\n' "$1"
}

warn() {
    printf '\033[1;33mWARNUNG:\033[0m %s\n' "$1"
}

fail() {
    printf '\n\033[1;31mFEHLER:\033[0m %s\n' "$1" >&2
    exit 1
}

if ((EUID != 0)); then
    exec sudo bash "$0" "$@"
fi

CALLING_USER="${SUDO_USER:-}"

if test -z "$CALLING_USER" || test "$CALLING_USER" = "root"; then
    CALLING_USER="$(logname 2>/dev/null || true)"
fi

test -n "$CALLING_USER" ||
    fail "Der aufrufende Benutzer konnte nicht ermittelt werden."

CALLING_GROUP="$(id -gn "$CALLING_USER")"

docker_works() {
    systemctl is-active --quiet docker.service &&
    timeout 20 docker info >/dev/null 2>&1 &&
    timeout 20 docker compose version >/dev/null 2>&1
}

install_docker() {
    section "Docker installieren oder reparieren"

    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y ca-certificates curl gnupg

    PACKAGES=(docker.io)

    if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
        PACKAGES+=(docker-compose-plugin)
    elif apt-cache show docker-compose-v2 >/dev/null 2>&1; then
        PACKAGES+=(docker-compose-v2)
    elif apt-cache show docker-compose >/dev/null 2>&1; then
        PACKAGES+=(docker-compose)
    else
        fail "Kein Docker-Compose-v2-Paket in den konfigurierten Paketquellen gefunden."
    fi

    apt-get install -y --reinstall "${PACKAGES[@]}"

    systemctl daemon-reload
    systemctl enable docker.service >/dev/null
    systemctl reset-failed docker.service 2>/dev/null || true
    systemctl restart docker.service

    for TRY in $(seq 1 30); do
        docker_works && return 0
        sleep 2
    done

    return 1
}

section "Docker prüfen"

if docker_works; then
    ok "Docker Engine und Docker Compose funktionieren."
else
    warn "Docker reagiert nicht korrekt. Versuche einen Neustart."

    systemctl daemon-reload
    systemctl reset-failed docker.service 2>/dev/null || true
    systemctl restart docker.service 2>/dev/null || true

    for TRY in $(seq 1 15); do
        docker_works && break
        sleep 2
    done

    if docker_works; then
        ok "Docker funktioniert nach dem Neustart."
    else
        warn "Docker funktioniert weiterhin nicht. Installation wird repariert."

        install_docker ||
            fail "Docker funktioniert auch nach der Neuinstallation nicht."

        ok "Docker wurde erfolgreich installiert beziehungsweise repariert."
    fi
fi

section "Zielverzeichnis"

read -r -p "ROOT [$DEFAULT_ROOT]: " ROOT
ROOT="${ROOT:-$DEFAULT_ROOT}"

case "$ROOT" in
    /opt/*)
        ;;
    *)
        fail "ROOT muss aus Sicherheitsgründen unter /opt liegen."
        ;;
esac

COMPOSE="$ROOT/compose.yaml"
ENV_FILE="$ROOT/.env"

install -d \
    -o "$CALLING_USER" \
    -g "$CALLING_GROUP" \
    -m 0755 \
    "$ROOT"

info "Zielverzeichnis: $ROOT"

section "Compose-Datei erstellen"

cat > "$COMPOSE" <<'COMPOSE_YAML'
name: jellyfin-media-stack
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./config/portainer:/data"
    restart: always
  cloudflared:
    profiles: [always-active]
    image: cloudflare/cloudflared:latest
    container_name: cloudflared-jfms
    command: ["tunnel", "--no-autoupdate", "run", "--token", "${CLOUDFLARE_API_KEY}"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    restart: always
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    environment: {TZ: "${TZ}"}
    volumes:
      - "./config/jellyfin/config:/config"
      - "./data/jellyfin/cache:/cache"
      - "${MEDIA}:/media"
    restart: unless-stopped
  tdarr:
    image: ghcr.io/haveagitgat/tdarr:latest
    container_name: tdarr
    environment: {TZ: "${TZ}", PUID: "${PUID}", PGID: "${PGID}", serverIP: "0.0.0.0", serverPort: "8266", webUIPort: "8265", internalNode: "true", inContainer: "true", auth: "true", apiKey: "${TDARR_API_KEY}"}
    volumes:
      - "./config/tdarr/server:/app/server"
      - "./config/tdarr/configs:/app/configs"
      - "./data/tdarr/logs:/app/logs"
      - "./data/tdarr/temp:/temp"
      - "${MEDIA}:/media"
    restart: unless-stopped
  iptv-epg:
    image: ghcr.io/iptv-org/epg:master
    profiles: [disabled]
    container_name: iptv-epg
    environment: {TZ: "${TZ}", CRON_SCHEDULE: "30 2 * * *", DAYS: "7", RUN_AT_STARTUP: "true"}
    volumes:
      - "./data/iptv-epg/public:/epg/public"
      - "${IPTV_CHANNELS_XML}:/epg/channels.xml:ro"
    restart: unless-stopped
  iptv-epg-arte:
    image: ghcr.io/iptv-org/epg:master
    container_name: iptv-epg-arte
    environment: {TZ: "${TZ}", CRON_SCHEDULE: "30 3 * * *", DAYS: "7", RUN_AT_STARTUP: "true"}
    volumes:
      - "./data/iptv-epg-arte/public:/epg/public"
      - "${IPTV_ARTE_CHANNELS_XML}:/epg/channels.xml:ro"
    restart: unless-stopped
COMPOSE_YAML

chown "$CALLING_USER:$CALLING_GROUP" "$COMPOSE"
chmod 0640 "$COMPOSE"

if grep -Fxq '# HIER COMPOSE EINFÜGEN' "$COMPOSE"; then
    echo
    echo "Die Vorlage wurde angelegt:"
    echo "  $COMPOSE"
    echo
    echo "Füge jetzt deine vollständige Compose-Datei an der markierten Stelle ein."
    echo "Starte dieses Setup-Skript danach erneut."
    exit 0
fi

section "Umgebungsvariablen"

prompt_value() {
    local VARIABLE="$1"
    local DESCRIPTION="$2"
    local DEFAULT="$3"
    local VALUE

    read -r -p "$DESCRIPTION [$DEFAULT]: " VALUE
    VALUE="${VALUE:-$DEFAULT}"

    printf -v "$VARIABLE" '%s' "$VALUE"
}

prompt_secret() {
    local VARIABLE="$1"
    local DESCRIPTION="$2"
    local VALUE

    read -r -s -p "$DESCRIPTION: " VALUE
    echo

    while test -z "$VALUE"; do
        warn "Der Wert darf nicht leer sein."
        read -r -s -p "$DESCRIPTION: " VALUE
        echo
    done

    printf -v "$VARIABLE" '%s' "$VALUE"
}

prompt_value PUID "PUID" "1000"
prompt_value PGID "PGID" "1000"
prompt_value TZ "Zeitzone" "Europe/Berlin"
prompt_value MEDIA "Internxt-Mount" "/mnt/internxt"
prompt_value IPTV_CHANNELS_XML \
    "IPTV channels.xml" \
    "/mnt/internxt/jellyfin/livetv/channels.xml"
prompt_value IPTV_ARTE_CHANNELS_XML \
    "IPTV Arte channels.xml" \
    "/mnt/internxt/jellyfin/livetv/arte-channels.xml"

prompt_secret TDARR_API_KEY "Tdarr API-Key"
prompt_secret CLOUDFLARE_API_KEY "Cloudflare-Tunnel-Token"

cat > "$ENV_FILE" <<ENV
NAME=$NAME
PUID=$PUID
PGID=$PGID
TZ=$TZ
MEDIA=$MEDIA
IPTV_CHANNELS_XML=$IPTV_CHANNELS_XML
IPTV_ARTE_CHANNELS_XML=$IPTV_ARTE_CHANNELS_XML
TDARR_API_KEY=$TDARR_API_KEY
CLOUDFLARE_API_KEY=$CLOUDFLARE_API_KEY
ENV

chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"

ok ".env wurde unter $ENV_FILE angelegt."

section "Internxt-Mount prüfen"

if ! mountpoint -q "$MEDIA"; then
    fail "$MEDIA ist nicht als eigener Mount eingebunden."
fi

if ! timeout --kill-after=2 10 \
    sudo -u "$CALLING_USER" ls -la "$MEDIA" >/dev/null 2>&1
then
    fail "$MEDIA ist gemountet, reagiert aber nicht korrekt."
fi

ok "Internxt-Mount ist erreichbar."

section "Compose validieren"

cd "$ROOT"

if ! docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE" \
    config --quiet
then
    fail "Die Compose-Datei ist ungültig."
fi

mapfile -t SERVICES < <(
    docker compose \
        --env-file "$ENV_FILE" \
        -f "$COMPOSE" \
        config --services
)

printf 'Services: %s\n' "${SERVICES[*]}"
ok "Compose-Datei ist gültig."

section "Images laden"

docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE" \
    --profile always-active \
    pull

section "Always-active-Profil starten"

if printf '%s\n' "${SERVICES[@]}" |
    grep -Fxq "$COMPOSE_SERVICE_ALWAYS"
then
    docker compose \
        --env-file "$ENV_FILE" \
        -f "$COMPOSE" \
        --profile always-active \
        up -d "$COMPOSE_SERVICE_ALWAYS"

    ok "$COMPOSE_SERVICE_ALWAYS wurde gezielt gestartet."
else
    fail "Der erwartete Service $COMPOSE_SERVICE_ALWAYS fehlt in der Compose-Datei."
fi

section "Standarddienste starten"

docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE" \
    up -d

section "Ergebnis"

docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE" \
    --profile always-active \
    ps -a

echo
ok "JFMS wurde eingerichtet."
echo
echo "Projekt:       $NAME"
echo "Verzeichnis:   $ROOT"
echo "Compose:       $COMPOSE"
echo "Umgebung:      $ENV_FILE"
echo "Benutzer:      $CALLING_USER"
echo "Medien:        $MEDIA"
echo
echo "Cloudflared wurde separat über das Profil always-active gestartet."
echo "Anschließend wurden alle profilfreien Standarddienste gestartet."
