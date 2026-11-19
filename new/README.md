# Setup Jellyfin Media Stack

### rclone if needet
```
sudo bash -c 'set -Eeuo pipefail; clear; U="${SUDO_USER:-$(logname 2>/dev/null || true)}"; test -n "$U" && test "$U" != root || { echo "FEHLER: Benutzer nicht erkannt"; exit 1; }; G="$(id -gn "$U")"; H="$(getent passwd "$U" | cut -d: -f6)"; C="$H/.config/rclone/rclone.conf"; M="/mnt/internxt"; V="/var/cache/rclone-internxt"; N="rclone-internxt.service"; F="/etc/systemd/system/$N"; D="/etc/systemd/system/$N.d"; O="$D/override.conf"; fail(){ echo; echo "FEHLER: $*" >&2; exit 1; }; step(){ echo; echo "=== $* ==="; }; version_ok(){ command -v rclone >/dev/null 2>&1 || return 1; local VSN; VSN="$(rclone version 2>/dev/null | head -1 | sed -E "s/^rclone v([0-9]+\.[0-9]+\.[0-9]+).*/\1/")"; test -n "$VSN" || return 1; dpkg --compare-versions "$VSN" ge "1.73.0"; }; healthy(){ timeout 5 systemctl is-active --quiet "$N" && timeout 5 mountpoint -q "$M" && timeout --kill-after=2 8 sudo -u "$U" -H ls -U "$M" >/dev/null 2>&1; }; step "INTERNXT SETUP"; echo "Benutzer: $U"; echo "Home:     $H"; step "1/6 VORAUSSETZUNGEN"; X=(); dpkg -s fuse3 >/dev/null 2>&1 || X+=(fuse3); command -v curl >/dev/null 2>&1 || X+=(curl); command -v unzip >/dev/null 2>&1 || X+=(unzip); if ((${#X[@]})); then echo "Installiere: ${X[*]}"; apt-get update -qq; apt-get install -y -qq "${X[@]}" >/tmp/internxt-apt.log 2>&1 || { tail -40 /tmp/internxt-apt.log; fail "Paketinstallation fehlgeschlagen"; }; else echo "Pakete: OK"; fi; test -e /dev/fuse || fail "/dev/fuse fehlt"; if version_ok; then echo "rclone: $(rclone version | head -1), Internxt-kompatibel"; else echo "rclone fehlt oder ist älter als v1.73.0, installiere aktuelle Version"; curl -fsSL https://rclone.org/install.sh -o /tmp/rclone-install.sh || fail "Installer konnte nicht geladen werden"; bash /tmp/rclone-install.sh >/tmp/rclone-install.log 2>&1 || true; rm -f /tmp/rclone-install.sh; version_ok || { tail -40 /tmp/rclone-install.log 2>/dev/null || true; fail "Keine Internxt-kompatible rclone-Version installiert"; }; echo "rclone: $(rclone version | head -1), Installation OK"; fi; touch /etc/fuse.conf; grep -qxF user_allow_other /etc/fuse.conf || { echo user_allow_other >>/etc/fuse.conf; echo "FUSE: user_allow_other ergänzt"; }; install -d -o "$U" -g "$G" -m 0700 "$(dirname "$C")"; install -d -o "$U" -g "$G" -m 0750 "$V"; step "2/6 INTERNXT-REMOTE"; if ! test -s "$C" || ! timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:"; then echo "Remote internxt: fehlt. Interaktive Einrichtung startet."; echo "Remote bitte exakt internxt nennen."; sudo -u "$U" -H rclone --config "$C" config; fi; timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:" || fail "Remote internxt: fehlt"; chown "$U:$G" "$C"; chmod 600 "$C"; echo "Remote internxt: OK"; step "3/6 SYSTEMD"; T="$(mktemp)"; Q="$(mktemp)"; trap "rm -f \"$T\" \"$Q\" /tmp/internxt-apt.log /tmp/rclone-install.log /tmp/internxt-verify.log" EXIT; printf "%s\n" "[Unit]" "Description=Internxt rclone mount for $U" "Wants=network-online.target" "After=network-online.target" "Before=docker.service" "RequiresMountsFor=/mnt" "" "[Service]" "Type=notify" "User=$U" "Group=$G" "ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=$C --cache-dir=$V --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO" "ExecStop=/bin/fusermount3 -uz /mnt/internxt" "Restart=on-failure" "RestartSec=10" "TimeoutStartSec=90" "TimeoutStopSec=30" "KillMode=mixed" "" "[Install]" "WantedBy=multi-user.target" >"$T"; printf "%s\n" "[Service]" "MemoryLow=128M" "MemoryHigh=512M" "MemoryMax=768M" "MemorySwapMax=256M" "CPUWeight=100" >"$Q"; Z=0; if test -f "$F" && cmp -s "$T" "$F"; then echo "Dienstdatei: korrekt"; else install -o root -g root -m 0644 "$T" "$F"; Z=1; echo "Dienstdatei: korrigiert"; fi; install -d -m 0755 "$D"; if test -f "$O" && cmp -s "$Q" "$O"; then echo "Ressourcenlimits: korrekt"; else install -o root -g root -m 0644 "$Q" "$O"; Z=1; echo "Ressourcenlimits: korrigiert"; fi; timeout 15 systemctl daemon-reload || fail "daemon-reload fehlgeschlagen"; timeout 15 systemd-analyze verify "$F" >/tmp/internxt-verify.log 2>&1 || { cat /tmp/internxt-verify.log; fail "Systemd-Konfiguration ungültig"; }; timeout 15 systemctl enable "$N" >/dev/null 2>&1 || fail "Dienst konnte nicht aktiviert werden"; systemctl reset-failed "$N" 2>/dev/null || true; step "4/6 MOUNT PRÜFEN"; if healthy; then echo "Mount: gesund, kein Neustart"; test "$Z" -eq 0 || echo "Neue Dienstkonfiguration gilt beim nächsten Remount."; else step "5/6 MOUNT REPARIEREN"; timeout --kill-after=10 120 systemctl stop "$N" >/dev/null 2>&1 || true; mapfile -t P < <(pgrep -f "^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)" || true); if ((${#P[@]})); then kill -TERM "${P[@]}" 2>/dev/null || true; sleep 5; for I in "${P[@]}"; do kill -0 "$I" 2>/dev/null && kill -KILL "$I" 2>/dev/null || true; done; fi; timeout 20 fusermount3 -uz "$M" 2>/dev/null || timeout 20 umount -fl "$M" 2>/dev/null || true; sleep 3; findmnt --mountpoint "$M" >/dev/null 2>&1 && { timeout 20 umount -fl "$M" 2>/dev/null || true; sleep 3; }; findmnt --mountpoint "$M" >/dev/null 2>&1 && fail "Alter FUSE-Mount weiterhin registriert"; rm -rf "$M"; install -d -o "$U" -g "$G" -m 0775 "$M"; install -d -o "$U" -g "$G" -m 0750 "$V"; echo "Starte Dienst"; systemctl start "$N" >/dev/null 2>&1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienststart fehlgeschlagen"; }; K=0; for I in $(seq 1 60); do if healthy; then K=1; break; fi; if systemctl is-failed --quiet "$N"; then journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienst fehlgeschlagen"; fi; printf "\rWarte: %3d/120 Sekunden" "$((I*2))"; sleep 2; done; echo; test "$K" -eq 1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Mount nicht erreichbar"; }; echo "Mount: repariert"; fi; step "6/6 ERGEBNIS"; healthy || fail "Abschlussprüfung fehlgeschlagen"; echo "Status:   ERFOLG"; echo "rclone:   $(rclone version | head -1)"; echo "Benutzer: $U"; findmnt --mountpoint "$M" -o TARGET,SOURCE,FSTYPE,OPTIONS; echo; timeout 10 sudo -u "$U" -H ls -Ula "$M" | head -20; echo; echo "Docker und andere Projekte wurden nicht neu gestartet."'
```
---
## commands
```
sudo nano ~/setup-jfms.sh && sudo chmod +x ~/setup-jfms.sh && sudo ~/setup-jfms.sh && sudo rm ~/setup-jfms.sh
```

### input
```
#!/usr/bin/env bash
set -Eeuo pipefail

clear
cat <<'EOF'
#### #### #... #... #..# #### #### #..#   #..# #### ###. #### .##.   .### #### .##. .### #..#
...# #... #... #... #..# #... .##. ##.#   ##.# #... #..# .##. #..#   #... .##. #..# #... #.#.
...# ###. #... #... .##. ###. .##. #.##   #.## ###. #..# .##. ####   .### .##. #### #... ##..
#..# #... #... #... ..#. #... .##. #..#   #..# #... #..# .##. #..#   ...# .##. #..# #... #.#.
.##. #### #### #### ..#. #... #### #..#   #..# #### ###. #### #..#   ###. .##. #..# .### #..#
EOF
echo "v2"
cat <<'EOF'
     _      _____ _     _     __ _          __  __          _ _          ____ _____ _   ____  _  __
    | |    | ____| |   | |   / _(_)_ __    |  \/  | ___  __| (_) __ _   / ___|_   _/ \ / ___|| |/ /
    | |    |  _| | |   | |  | |_| | '_ \   | |\/| |/ _ \/ _` | |/ _` |  \___ \ | |/ _ \| |   | ' /
    | |___ | |___| |___| |__|  _| | | | |  | |  | |  __/ (_| | | (_| |  ___) || / ___ \ |___| . \
    |_____|_____|_____|_____|_| |_|_| |_|  |_|  |_|\___|\__,_|_|\__,_|  |____/ |_/_/   \_\____|_|\_\
---
---



EOF
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
        --profile always-active \
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

if docker compose \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE" \
    --profile always-active \
    config --services |
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
```
