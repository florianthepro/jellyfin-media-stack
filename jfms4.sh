#!/usr/bin/env bash
set -Eeuo pipefail

# NEU: v1.2.0 - Live-Modus, Menüpunkt 1 = install/update
VERSION="v1.2.0"
SELF_URL="https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/jfms4.sh"

INSTALL_MENU=/usr/local/sbin/jfms
INSTALL_RCLONE=/usr/local/sbin/jfms-rclone-setup
INSTALL_JFMS=/usr/local/sbin/jfms-jellyfin-setup
INSTALL_BACKUP=/usr/local/sbin/jfms-backup
SVC_BACKUP=/etc/systemd/system/jfms-backup.service
SVC_BACKUP_TIMER=/etc/systemd/system/jfms-backup.timer
SVC_RCLONE=/etc/systemd/system/rclone-internxt.service
SVC_STACK=/etc/systemd/system/jfms-stack.service
BACKUP_ROOT=/opt/jfms
BACKUP_DIR=/opt/jfms/backup
COMPOSE_FILE=/opt/jfms/compose.yaml
ENV_FILE=/opt/jfms/.env

# ---------- Log ----------
fail()    { printf '\n\033[1;31mFEHLER:\033[0m %s\n'  "$*" >&2; exit 1; }
ok()      { printf '\033[1;32mOK:\033[0m %s\n'        "$*"; }
info()    { printf '\033[1;34mINFO:\033[0m %s\n'      "$*"; }
warn()    { printf '\033[1;33mWARNUNG:\033[0m %s\n'   "$*"; }
section() { printf '\n\033[1;36m%s\033[0m\n' "=== $* ==="; }
step()    { section "$*"; }

# ---------- rclone-Helfer ----------
version_ok() {
    command -v rclone >/dev/null 2>&1 || return 1
    local VSN
    VSN="$(rclone version 2>/dev/null | head -1 | sed -E 's/^rclone v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
    test -n "$VSN" || return 1
    dpkg --compare-versions "$VSN" ge "1.73.0"
}
rclone_healthy() {
    local U=$1 M=$2 N=$3
    timeout 5 systemctl is-active --quiet "$N" \
        && timeout 5 mountpoint -q "$M" \
        && timeout --kill-after=2 8 sudo -u "$U" -H ls -U "$M" >/dev/null 2>&1
}

# ---------- jellyfin-Helfer ----------
docker_works() {
    systemctl is-active --quiet docker.service \
        && timeout 20 docker info >/dev/null 2>&1 \
        && timeout 20 docker compose version >/dev/null 2>&1
}
install_docker() {
    section "Docker installieren oder reparieren"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    local -a PACKAGES=(docker.io)
    if   apt-cache show docker-compose-plugin >/dev/null 2>&1; then PACKAGES+=(docker-compose-plugin)
    elif apt-cache show docker-compose-v2    >/dev/null 2>&1; then PACKAGES+=(docker-compose-v2)
    elif apt-cache show docker-compose       >/dev/null 2>&1; then PACKAGES+=(docker-compose)
    else fail "Kein Docker-Compose-v2-Paket gefunden."
    fi
    apt-get install -y --reinstall "${PACKAGES[@]}"
    systemctl daemon-reload
    systemctl enable docker.service >/dev/null
    systemctl reset-failed docker.service 2>/dev/null || true
    systemctl restart docker.service
    local TRY
    for TRY in $(seq 1 30); do docker_works && return 0; sleep 2; done
    return 1
}
prompt_value() {
    local VARIABLE="$1" DESC="$2" DEFAULT="$3" VALUE
    read -r -p "$DESC [$DEFAULT]: " VALUE
    VALUE="${VALUE:-$DEFAULT}"
    printf -v "$VARIABLE" '%s' "$VALUE"
}
prompt_secret() {
    local VARIABLE="$1" DESC="$2" VALUE
    read -r -s -p "$DESC: " VALUE; echo
    while test -z "$VALUE"; do
        warn "Der Wert darf nicht leer sein."
        read -r -s -p "$DESC: " VALUE; echo
    done
    printf -v "$VARIABLE" '%s' "$VALUE"
}

# ============================================================
# rclone / Internxt  (unverändert)
# ============================================================
rclone_main() {
    local U G H C M V N UNIT D O
    [[ -t 1 ]] && clear 2>/dev/null || true
    U="${SUDO_USER:-$(logname 2>/dev/null || true)}"
    test -n "$U" && test "$U" != root || fail "Benutzer nicht erkannt"
    G="$(id -gn "$U")"
    H="$(getent passwd "$U" | cut -d: -f6)"
    C="$H/.config/rclone/rclone.conf"
    M=/mnt/internxt
    V=/var/cache/rclone-internxt
    N=rclone-internxt.service
    UNIT=$SVC_RCLONE
    D=/etc/systemd/system/$N.d
    O=$D/override.conf
    step "INTERNXT SETUP"; echo "Benutzer: $U"; echo "Home:     $H"
    step "1/6 VORAUSSETZUNGEN"
    local -a X=()
    dpkg -s fuse3 >/dev/null 2>&1 || X+=(fuse3)
    command -v curl  >/dev/null 2>&1 || X+=(curl)
    command -v unzip >/dev/null 2>&1 || X+=(unzip)
    if ((${#X[@]})); then
        echo "Installiere: ${X[*]}"
        apt-get update -qq
        apt-get install -y -qq "${X[@]}" >/tmp/internxt-apt.log 2>&1 \
            || { tail -40 /tmp/internxt-apt.log; fail "Paketinstallation fehlgeschlagen"; }
    else echo "Pakete: OK"; fi
    test -e /dev/fuse || fail "/dev/fuse fehlt"
    if version_ok; then echo "rclone: $(rclone version | head -1), Internxt-kompatibel"
    else
        echo "rclone fehlt oder < v1.73.0, installiere aktuelle Version"
        curl -fsSL https://rclone.org/install.sh -o /tmp/rclone-install.sh || fail "Installer konnte nicht geladen werden"
        bash /tmp/rclone-install.sh >/tmp/rclone-install.log 2>&1 || true
        rm -f /tmp/rclone-install.sh
        version_ok || { tail -40 /tmp/rclone-install.log 2>/dev/null || true; fail "Keine Internxt-kompatible rclone-Version installiert"; }
        echo "rclone: $(rclone version | head -1), Installation OK"
    fi
    touch /etc/fuse.conf
    grep -qxF user_allow_other /etc/fuse.conf || { echo user_allow_other >>/etc/fuse.conf; echo "FUSE: user_allow_other ergänzt"; }
    install -d -o "$U" -g "$G" -m 0700 "$(dirname "$C")"
    install -d -o "$U" -g "$G" -m 0750 "$V"
    step "2/6 INTERNXT-REMOTE"
    if ! test -s "$C" || ! timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:"; then
        echo "Remote internxt fehlt. Interaktive Einrichtung startet."
        echo "Remote bitte exakt 'internxt' nennen."
        sudo -u "$U" -H rclone --config "$C" config
    fi
    timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:" || fail "Remote internxt fehlt"
    chown "$U:$G" "$C"; chmod 600 "$C"; echo "Remote internxt: OK"
    step "3/6 SYSTEMD"
    local T Q
    T=$(mktemp); Q=$(mktemp)
    trap 'rm -f "$T" "$Q" /tmp/internxt-apt.log /tmp/rclone-install.log /tmp/internxt-verify.log' EXIT
    printf '%s\n' \
        "[Unit]" "Description=Internxt rclone mount for $U" \
        "Wants=network-online.target" "After=network-online.target" \
        "Before=docker.service" "RequiresMountsFor=/mnt" "" \
        "[Service]" "Type=notify" "User=$U" "Group=$G" \
        "ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=$C --cache-dir=$V --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO" \
        "ExecStop=/bin/fusermount3 -uz /mnt/internxt" "Restart=on-failure" \
        "RestartSec=10" "TimeoutStartSec=90" "TimeoutStopSec=30" "KillMode=mixed" "" \
        "[Install]" "WantedBy=multi-user.target" > "$T"
    printf '%s\n' \
        "[Service]" "MemoryLow=128M" "MemoryHigh=512M" "MemoryMax=768M" \
        "MemorySwapMax=256M" "CPUWeight=100" > "$Q"
    local Z=0
    if test -f "$UNIT" && cmp -s "$T" "$UNIT"; then echo "Dienstdatei: korrekt"
    else install -o root -g root -m 0644 "$T" "$UNIT"; Z=1; echo "Dienstdatei: korrigiert"; fi
    install -d -m 0755 "$D"
    if test -f "$O" && cmp -s "$Q" "$O"; then echo "Ressourcenlimits: korrekt"
    else install -o root -g root -m 0644 "$Q" "$O"; Z=1; echo "Ressourcenlimits: korrigiert"; fi
    timeout 15 systemctl daemon-reload || fail "daemon-reload fehlgeschlagen"
    timeout 15 systemd-analyze verify "$UNIT" >/tmp/internxt-verify.log 2>&1 \
        || { cat /tmp/internxt-verify.log; fail "Systemd-Konfiguration ungültig"; }
    timeout 15 systemctl enable "$N" >/dev/null 2>&1 || fail "Dienst konnte nicht aktiviert werden"
    systemctl reset-failed "$N" 2>/dev/null || true
    step "4/6 MOUNT PRÜFEN"
    if rclone_healthy "$U" "$M" "$N"; then
        echo "Mount: gesund, kein Neustart"
        test "$Z" -eq 0 || echo "Neue Dienstkonfiguration gilt beim nächsten Remount."
    else
        step "5/6 MOUNT REPARIEREN"
        timeout --kill-after=10 120 systemctl stop "$N" >/dev/null 2>&1 || true
        local -a P=()
        mapfile -t P < <(pgrep -f '^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)' || true)
        if ((${#P[@]})); then
            kill -TERM "${P[@]}" 2>/dev/null || true; sleep 5
            local I
            for I in "${P[@]}"; do kill -0 "$I" 2>/dev/null && kill -KILL "$I" 2>/dev/null || true; done
        fi
        timeout 20 fusermount3 -uz "$M" 2>/dev/null || timeout 20 umount -fl "$M" 2>/dev/null || true
        sleep 3
        findmnt --mountpoint "$M" >/dev/null 2>&1 && { timeout 20 umount -fl "$M" 2>/dev/null || true; sleep 3; }
        findmnt --mountpoint "$M" >/dev/null 2>&1 && fail "Alter FUSE-Mount weiterhin registriert"
        rm -rf "$M"
        install -d -o "$U" -g "$G" -m 0775 "$M"
        install -d -o "$U" -g "$G" -m 0750 "$V"
        echo "Starte Dienst"
        systemctl start "$N" >/dev/null 2>&1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienststart fehlgeschlagen"; }
        local K=0 I
        for I in $(seq 1 60); do
            if rclone_healthy "$U" "$M" "$N"; then K=1; break; fi
            if systemctl is-failed --quiet "$N"; then journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienst fehlgeschlagen"; fi
            printf '\rWarte: %3d/120 Sekunden' "$((I*2))"; sleep 2
        done; echo
        test "$K" -eq 1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Mount nicht erreichbar"; }
        echo "Mount: repariert"
    fi
    step "6/6 ERGEBNIS"
    rclone_healthy "$U" "$M" "$N" || fail "Abschlussprüfung fehlgeschlagen"
    echo "Status:   ERFOLG"
    echo "rclone:   $(rclone version | head -1)"
    echo "Benutzer: $U"
    findmnt --mountpoint "$M" -o TARGET,SOURCE,FSTYPE,OPTIONS
    echo; timeout 10 sudo -u "$U" -H ls -Ula "$M" | head -20; echo
    echo "Docker und andere Projekte wurden nicht neu gestartet."
}

# ============================================================
# Jellyfin Stack (unverändert)
# ============================================================
jellyfin_main() {
    local NAME="jellyfin-media-stack"
    local DEFAULT_ROOT="/opt/jfms"
    local COMPOSE_SERVICE_ALWAYS="cloudflared"
    [[ -t 1 ]] && clear 2>/dev/null || true
    cat <<'BANNER'
#### #### #... #... #..# #### #### #..#   #..# #### ###. #### .##.   .### #### .##. .### #..#
...# #... #... #... #..# #... .##. ##.#   ##.# #... #..# .##. #..#   #... .##. #..# #... #.#.
...# ###. #... #... .##. ###. .##. #.##   #.## ###. #..# .##. ####   .### .##. #### #... ##..
#..# #... #... #... ..#. #... .##. #..#   #..# #... #..# .##. #..#   ...# .##. #..# #... #.#.
.##. #### #### #### ..#. #... #### #..#   #..# #### ###. #### #..#   ###. .##. #..# .### #..#
BANNER
    echo "v2"
    if ((EUID != 0)); then exec sudo bash "$0" "$@"; fi
    local CALLING_USER="${SUDO_USER:-}"
    test -n "$CALLING_USER" && test "$CALLING_USER" != root || CALLING_USER="$(logname 2>/dev/null || true)"
    test -n "$CALLING_USER" || fail "Der aufrufende Benutzer konnte nicht ermittelt werden."
    local CALLING_GROUP="$(id -gn "$CALLING_USER")"
    section "Docker prüfen"
    if docker_works; then ok "Docker Engine und Docker Compose funktionieren."
    else
        warn "Docker reagiert nicht korrekt. Versuche Neustart."
        systemctl daemon-reload; systemctl reset-failed docker.service 2>/dev/null || true
        systemctl restart docker.service 2>/dev/null || true
        local TRY
        for TRY in $(seq 1 15); do docker_works && break; sleep 2; done
        if docker_works; then ok "Docker funktioniert nach dem Neustart."
        else
            warn "Docker funktioniert weiterhin nicht. Installation wird repariert."
            install_docker || fail "Docker funktioniert auch nach Neuinstallation nicht."
            ok "Docker wurde erfolgreich installiert bzw. repariert."
        fi
    fi
    section "Zielverzeichnis"
    local ROOT
    read -r -p "ROOT [$DEFAULT_ROOT]: " ROOT; ROOT="${ROOT:-$DEFAULT_ROOT}"
    case "$ROOT" in /opt/*) ;; *) fail "ROOT muss unter /opt liegen.";; esac
    local COMPOSE="$ROOT/compose.yaml"
    local ENV_FILE_LOCAL="$ROOT/.env"
    install -d -o "$CALLING_USER" -g "$CALLING_GROUP" -m 0755 "$ROOT"
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
      - "${MEDIA}:/media:ro"
      - "${MEDIA}/jellyfin/livetv/recordings:/media/jellyfin/livetv/recordings:rw"
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
      - "${MEDIA}:/media:ro"
      - "${MEDIA}/tdarr:/media/tdarr:rw"
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
    chown "$CALLING_USER:$CALLING_GROUP" "$COMPOSE"; chmod 0640 "$COMPOSE"
    section "Umgebungsvariablen"
    local PUID PGID TZ MEDIA IPTV_CHANNELS_XML IPTV_ARTE_CHANNELS_XML TDARR_API_KEY CLOUDFLARE_API_KEY
    prompt_value PUID "PUID" "1000"
    prompt_value PGID "PGID" "1000"
    prompt_value TZ "Zeitzone" "Europe/Berlin"
    prompt_value MEDIA "Internxt-Mount" "/mnt/internxt"
    prompt_value IPTV_CHANNELS_XML "IPTV channels.xml" "/mnt/internxt/jellyfin/livetv/channels.xml"
    prompt_value IPTV_ARTE_CHANNELS_XML "IPTV Arte channels.xml" "/mnt/internxt/jellyfin/livetv/arte-channels.xml"
    prompt_secret TDARR_API_KEY "Tdarr API-Key"
    prompt_secret CLOUDFLARE_API_KEY "Cloudflare-Tunnel-Token"
    cat > "$ENV_FILE_LOCAL" <<ENV
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
    chown root:root "$ENV_FILE_LOCAL"; chmod 0600 "$ENV_FILE_LOCAL"
    ok ".env wurde unter $ENV_FILE_LOCAL angelegt."
    section "Internxt-Mount prüfen"
    mountpoint -q "$MEDIA" || fail "$MEDIA ist nicht als eigener Mount eingebunden."
    timeout --kill-after=2 10 sudo -u "$CALLING_USER" ls -la "$MEDIA" >/dev/null 2>&1 \
        || fail "$MEDIA ist gemountet, reagiert aber nicht korrekt."
    ok "Internxt-Mount ist erreichbar."
    section "Compose validieren"
    cd "$ROOT"
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" config --quiet || fail "Die Compose-Datei ist ungültig."
    local -a SERVICES
    mapfile -t SERVICES < <(docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" --profile always-active config --services)
    printf 'Services: %s\n' "${SERVICES[*]}"
    ok "Compose-Datei ist gültig."
    section "Images laden"
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" --profile always-active pull
    section "Always-active-Profil starten"
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" --profile always-active config --services \
        | grep -Fxq "$COMPOSE_SERVICE_ALWAYS" || fail "Der erwartete Service $COMPOSE_SERVICE_ALWAYS fehlt."
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" --profile always-active up -d "$COMPOSE_SERVICE_ALWAYS"
    ok "$COMPOSE_SERVICE_ALWAYS wurde gezielt gestartet."
    section "Standarddienste starten"
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" up -d
    section "Ergebnis"
    docker compose --env-file "$ENV_FILE_LOCAL" -f "$COMPOSE" --profile always-active ps -a
    echo; ok "JFMS wurde eingerichtet."
}

# ============================================================
# Backup / Restore / Anzeigen  (unverändert)
# ============================================================
backup_main() {
    exec 9>/run/lock/jfms-backup.lock
    flock -w 2 9 || { echo "Backup läuft bereits."; return 1; }
    [[ -d "$BACKUP_ROOT/config" ]]       || { echo "Fehlt: $BACKUP_ROOT/config" >&2; return 1; }
    [[ -f "$BACKUP_ROOT/compose.yaml" ]] || { echo "Fehlt: $BACKUP_ROOT/compose.yaml" >&2; return 1; }
    mkdir -p "$BACKUP_DIR"
    local OLD_UMASK; OLD_UMASK=$(umask); umask 077
    local D N=1 F
    D=$(date +%Y%m%d); F="$BACKUP_DIR/jfms-config-$D-v$N.tar"
    while [[ -e "$F" ]]; do N=$((N+1)); F="$BACKUP_DIR/jfms-config-$D-v$N.tar"; done
    local TMP; TMP=$(mktemp "$BACKUP_DIR/.jfms-config-$D-v$N.XXXXXX")
    trap 'rm -f -- "$TMP" 2>/dev/null || true' EXIT
    tar --numeric-owner --acls --xattrs -cpf "$TMP" -C "$BACKUP_ROOT" config compose.yaml
    tar -tf "$TMP" >/dev/null
    mv -- "$TMP" "$F"; trap - EXIT; umask "$OLD_UMASK"
    local -a MATCHING=(); local FILE BASE
    for FILE in "$BACKUP_DIR"/jfms-config-*.tar; do
        [[ -f "$FILE" ]] || continue
        BASE=${FILE##*/}
        [[ "$BASE" =~ ^jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar$ ]] && MATCHING+=("$FILE")
    done
    if ((${#MATCHING[@]} > 3)); then
        local -a SORTED; mapfile -t SORTED < <(printf '%s\n' "${MATCHING[@]}" | sort -V)
        local RC=$((${#SORTED[@]} - 3)) I
        for ((I=0;I<RC;I++)); do rm -f -- "${SORTED[I]}"; done
    fi
    echo "Backup: $F"; sha256sum "$F" 2>/dev/null || true
    local SIP; SIP=$(awk '{print $1}' <<< "${SSH_CONNECTION:-}" 2>/dev/null || true)
    [[ -n "$SIP" ]] && printf 'scp "%s@%s:%s" /ziel/\n' "${USER:-root}" "$SIP" "$F"
}
restore_main() {
    exec 9>/run/lock/jfms-restore.lock
    flock -n 9 || { echo "Wiederherstellung läuft bereits."; return 1; }
    local W D
    read -r -p "Archiv: 1) /tmp  2) $BACKUP_DIR [2]: " W
    case "${W:-2}" in 1) D=/tmp;; 2) D="$BACKUP_DIR";; *) echo "Ungültig."; return 1;; esac
    [[ -d "$D" ]] || { echo "Fehlt: $D"; return 1; }
    local -a A
    mapfile -t A < <(find "$D" -maxdepth 1 -type f -regextype posix-extended -regex '.*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar' -printf '%f\n' | sort -V)
    ((${#A[@]})) || { echo "Keine Archive."; return 1; }
    printf '%s\n' "${A[@]}" | nl -v1
    local N; read -r -p "Nr [${#A[@]}]: " N; N=${N:-${#A[@]}}
    [[ "$N" =~ ^[0-9]+$ ]] || return 1
    local IX=$((10#$N-1)); ((IX>=0 && IX<${#A[@]})) || return 1
    local F="$D/${A[IX]}" T
    T=$(mktemp -d "$BACKUP_ROOT/.jfms-restore.XXXXXX")
    local COMMITTED=0
    local -a TARGETS=() BACKUPS=() HAD=() INSTALLED=()
    cleanup_restore() {
        local RC=$?; trap - EXIT
        if ((RC!=0 && COMMITTED==0)); then
            set +e; local I
            for ((I=${#TARGETS[@]}-1;I>=0;I--)); do
                ((INSTALLED[I])) && rm -rf -- "${TARGETS[I]}"
                ((HAD[I]))       && mv -- "${BACKUPS[I]}" "${TARGETS[I]}"
            done
        fi
        [[ -z "${T:-}" ]] || rm -rf -- "$T"; exit "$RC"
    }
    trap cleanup_restore EXIT
    tar -tf "$F" > "$T/members" || return 1
    local HC=0 HP=0 M
    while IFS= read -r M; do
        [[ "$M" != /* && ! "$M" =~ (^|/)\.\.(/|$) ]] || { echo "Unsicher: $M"; return 1; }
        case "$M" in config|config/|config/*) HC=1;; compose.yaml) HP=1;; *) echo "Unerwartet: $M"; return 1;; esac
    done < "$T/members"
    ((HC && HP)) || return 1
    mkdir "$T/new"
    tar --numeric-owner --acls --xattrs -xpf "$F" -C "$T/new" config compose.yaml
    [[ -d "$T/new/config" && -f "$T/new/compose.yaml" ]] || return 1
    local SCOPE; read -r -p "1) config/ ersetzen 2) Unterordner [1]: " SCOPE
    local ALL=0; local -a DIRS=()
    case "${SCOPE:-1}" in
        1) ALL=1;;
        2) [[ -d "$BACKUP_ROOT/config" ]] || return 1
           local -a AVAILABLE
           mapfile -t AVAILABLE < <(find "$T/new/config" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
           ((${#AVAILABLE[@]})) || return 1
           printf '%s\n' "${AVAILABLE[@]}" | nl -v1
           local PICKS; read -r -p "Nummern: " PICKS || return 1
           local -a PS; IFS=',' read -r -a PS <<< "$PICKS"
           local P J X Y DUP
           for P in "${PS[@]}"; do
               P=${P//[[:space:]]/}; [[ "$P" =~ ^[0-9]+$ ]] || return 1
               J=$((10#$P-1)); ((J>=0 && J<${#AVAILABLE[@]})) || return 1
               X=${AVAILABLE[J]}; DUP=0
               for Y in "${DIRS[@]}"; do [[ "$Y" == "$X" ]] && DUP=1; done
               ((DUP)) || DIRS+=("$X")
           done
           ((${#DIRS[@]})) || return 1;;
        *) return 1;;
    esac
    local CP RC_C=1; read -r -p "compose.yaml auch? [J/n]: " CP
    case "${CP,,}" in n|nein) RC_C=0;; esac
    replace() {
        local SRC=$1 DST=$2 I=${#TARGETS[@]} B="$T/old/$I"
        mkdir -p "$T/old"; TARGETS+=("$DST"); BACKUPS+=("$B"); HAD+=(0); INSTALLED+=(0)
        if [[ -e "$DST" || -L "$DST" ]]; then mv -- "$DST" "$B"; HAD[I]=1; fi
        mv -- "$SRC" "$DST"; INSTALLED[I]=1
    }
    local X
    if ((ALL)); then replace "$T/new/config" "$BACKUP_ROOT/config"
    else for X in "${DIRS[@]}"; do replace "$T/new/config/$X" "$BACKUP_ROOT/config/$X"; done; fi
    ((RC_C)) && replace "$T/new/compose.yaml" "$BACKUP_ROOT/compose.yaml"
    COMMITTED=1; rm -rf -- "$T"; T=; trap - EXIT
    echo "Wiederhergestellt."
    local ACTION; read -r -p "1) alle 2) auswählen 3) keine [3]: " ACTION; ACTION=${ACTION:-3}
    case "$ACTION" in 3) return 0;; 1|2) ;; *) return 1;; esac
    local -a DC=(docker compose --project-directory "$BACKUP_ROOT" -f "$BACKUP_ROOT/compose.yaml")
    local SERVICES_TEXT; SERVICES_TEXT=$("${DC[@]}" config --services) || return 1
    [[ -n "$SERVICES_TEXT" ]] || return 1
    local -a SERVICES; mapfile -t SERVICES <<< "$SERVICES_TEXT"
    if [[ "$ACTION" == 1 ]]; then "${DC[@]}" up -d
    else
        printf '%s\n' "${SERVICES[@]}" | nl -v1
        local PICKS; read -r -p "Nummern: " PICKS || return 1
        local -a PS; IFS=',' read -r -a PS <<< "$PICKS"
        local -a CHOSEN=(); local P J
        for P in "${PS[@]}"; do
            P=${P//[[:space:]]/}; [[ "$P" =~ ^[0-9]+$ ]] || return 1
            J=$((10#$P-1)); ((J>=0 && J<${#SERVICES[@]})) || return 1
            CHOSEN+=("${SERVICES[J]}")
        done
        ((${#CHOSEN[@]})) || return 1
        "${DC[@]}" up -d "${CHOSEN[@]}"
    fi
}
show_latest() {
    local F
    F=$(find "$BACKUP_DIR" -maxdepth 1 -type f -regextype posix-extended -regex '.*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar' -printf '%f\n' 2>/dev/null | sort -V | tail -n1)
    [[ -n "$F" ]] || { echo "Kein Backup vorhanden."; return 1; }
    echo "Inhalt: $F (Tiefe 1-4)"
    tar -tf "$BACKUP_DIR/$F" | awk -F/ 'NF <= 4'
}

# ============================================================
# Service-Installer (unverändert)
# ============================================================
install_service() {
    mkdir -p "$BACKUP_DIR"
    cat > "$SVC_BACKUP" <<EOF
[Unit]
Description=JFMS Backup
[Service]
Type=oneshot
ExecStart=$INSTALL_BACKUP
EOF
    cat > "$SVC_BACKUP_TIMER" <<EOF
[Unit]
Description=JFMS Backup Timer
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
Unit=jfms-backup.service
[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now jfms-backup.timer
    ok "Backup-Service aktiv (täglich 02:00)."
}
uninstall_service() {
    systemctl disable --now jfms-backup.timer 2>/dev/null || true
    rm -f "$SVC_BACKUP" "$SVC_BACKUP_TIMER"
    systemctl daemon-reload
    ok "Backup-Service entfernt."
}
install_stack_service() {
    [[ -f "$COMPOSE_FILE" ]] || { warn "Fehlt: $COMPOSE_FILE (erst JFMS-Setup, Punkt 7)."; return 1; }
    local -a ENVARGS=()
    [[ -f "$ENV_FILE" ]] && ENVARGS=(--env-file "$ENV_FILE")
    cat > "$SVC_STACK" <<EOF
[Unit]
Description=JFMS Docker Compose Stack
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$BACKUP_ROOT
ExecStart=/usr/bin/docker compose --project-directory $BACKUP_ROOT ${ENVARGS[*]:-} -f $COMPOSE_FILE up -d
ExecStop=/usr/bin/docker compose --project-directory $BACKUP_ROOT ${ENVARGS[*]:-} -f $COMPOSE_FILE down
TimeoutStartSec=300
TimeoutStopSec=180
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now jfms-stack.service
    ok "JFMS-Stack als systemd-Service installiert (Auto-Start bei Boot)."
}
uninstall_stack_service() {
    systemctl disable --now jfms-stack.service 2>/dev/null || true
    rm -f "$SVC_STACK"
    systemctl daemon-reload
    ok "JFMS-Stack-Service entfernt."
}

# ============================================================
# Services-Verwaltung (unverändert)
# ============================================================
SVC_NAMES=(jfms-backup rclone-internxt jfms-stack)
svc_unit() {
    case "$1" in
        jfms-backup)     echo jfms-backup.timer ;;
        rclone-internxt) echo rclone-internxt.service ;;
        jfms-stack)      echo jfms-stack.service ;;
    esac
}
svc_label() {
    case "$1" in
        jfms-backup)     echo "Auto-Backup (02:00)" ;;
        rclone-internxt) echo "rclone-Mount (Internxt)" ;;
        jfms-stack)      echo "JFMS-Stack (Compose)" ;;
    esac
}
svc_main_file() {
    case "$1" in
        jfms-backup)     echo "$SVC_BACKUP_TIMER" ;;
        rclone-internxt) echo "$SVC_RCLONE" ;;
        jfms-stack)      echo "$SVC_STACK" ;;
    esac
}
svc_exists() { [[ -f "$(svc_main_file "$1")" ]]; }
svc_outdated() {
    local name=$1
    [[ -f "$(svc_main_file "$name")" ]] || return 1
    case "$name" in
        jfms-backup)
            [[ -f "$SVC_BACKUP" ]] || return 0
            grep -qF "ExecStart=$INSTALL_BACKUP" "$SVC_BACKUP" || return 0
            grep -qF 'OnCalendar=' "$SVC_BACKUP_TIMER" || return 0 ;;
        rclone-internxt)
            grep -qE '^ExecStart=.*/rclone mount internxt:media /mnt/internxt' "$SVC_RCLONE" 2>/dev/null || return 0 ;;
        jfms-stack)
            grep -qF "WorkingDirectory=$BACKUP_ROOT" "$SVC_STACK" 2>/dev/null || return 0
            grep -qF "$COMPOSE_FILE" "$SVC_STACK" 2>/dev/null || return 0 ;;
    esac
    return 1
}
svc_line() {
    local name=$1 label main inst="nein" en="-" act="-" state="nicht installiert"
    label=$(svc_label "$name"); main=$(svc_unit "$name")
    if svc_exists "$name"; then
        inst="ja"
        systemctl is-enabled --quiet "$main" 2>/dev/null && en="ja"  || en="nein"
        systemctl is-active  --quiet "$main" 2>/dev/null && act="ja" || act="nein"
        if svc_outdated "$name"; then state="VERALTET"; else state="aktuell"; fi
    fi
    printf "%-26s %-11s %-8s %-6s %s\n" "$label" "$inst" "$en" "$act" "$state"
}
svc_install() {
    case "$1" in
        jfms-backup) install_service ;;
        rclone-internxt)
            if [[ -f "$SVC_RCLONE" ]]; then
                ok "Bereits vorhanden. Bei Problemen Punkt 6 (rclone-Setup) ausführen."
            else
                warn "Wird durch Punkt 6 (rclone/Internxt Setup) eingerichtet."
            fi ;;
        jfms-stack) install_stack_service ;;
    esac
}
svc_uninstall() {
    case "$1" in
        jfms-backup) uninstall_service ;;
        rclone-internxt)
            systemctl disable --now rclone-internxt.service 2>/dev/null || true
            rm -f "$SVC_RCLONE"; rm -rf "$SVC_RCLONE.d"
            systemctl daemon-reload
            ok "rclone-Mount-Service entfernt." ;;
        jfms-stack) uninstall_stack_service ;;
    esac
}
svc_configure() {
    case "$1" in
        jfms-backup)
            local t new_t
            t=$(grep -oP 'OnCalendar=\K.*' "$SVC_BACKUP_TIMER" 2>/dev/null || echo "*-*-* 02:00:00")
            info "Aktueller Zeitplan: $t"
            read -r -p "Neuer OnCalendar-Ausdruck [$t]: " new_t
            new_t="${new_t:-$t}"
            sed -i "s|^OnCalendar=.*|OnCalendar=$new_t|" "$SVC_BACKUP_TIMER"
            systemctl daemon-reload
            systemctl restart jfms-backup.timer 2>/dev/null || true
            ok "Zeitplan aktualisiert: $new_t" ;;
        rclone-internxt)
            info "Bearbeite $SVC_RCLONE"
            "${EDITOR:-nano}" "$SVC_RCLONE"
            systemctl daemon-reload
            systemctl restart rclone-internxt.service || true ;;
        jfms-stack)
            if [[ -f "$COMPOSE_FILE" ]]; then
                info "Bearbeite $COMPOSE_FILE"
                "${EDITOR:-nano}" "$COMPOSE_FILE"
                systemctl restart jfms-stack.service || true
            else warn "Fehlt: $COMPOSE_FILE"; fi ;;
    esac
}
manage_one_service() {
    local name=$1
    while true; do
        echo; section "$(svc_label "$name")"
        svc_line "$name"
        echo
        echo "1) Installieren / Reparieren"
        echo "2) Konfigurieren"
        echo "3) Deinstallieren"
        echo "4) Status / Logs"
        echo "5) Zurück"
        local C; read -r -p "Auswahl [5]: " C || return 0
        case "${C:-5}" in
            1) svc_install "$name" || true ;;
            2) svc_configure "$name" || true ;;
            3) svc_uninstall "$name" || true ;;
            4)
                systemctl status "$(svc_unit "$name")" --no-pager 2>/dev/null || true
                echo
                journalctl -u "$(svc_unit "$name")" -n 20 --no-pager 2>/dev/null || true ;;
            5) return 0 ;;
            *) echo "Ungültig" ;;
        esac
    done
}
manage_services() {
    local -a names=(jfms-backup rclone-internxt jfms-stack)
    while true; do
        echo; section "Services verwalten"
        printf "%-26s %-11s %-8s %-6s %s\n" "Service" "Installiert" "Enabled" "Aktiv" "Status"
        local i=1 name
        for name in "${names[@]}"; do printf "%d) " "$i"; svc_line "$name"; i=$((i+1)); done
        echo "$i) Alle reparieren/aktualisieren"; local opt_all=$i; i=$((i+1))
        echo "$i) Zurück"; local opt_back=$i
        local C; read -r -p "Auswahl: " C || return 0
        case "$C" in
            1) manage_one_service jfms-backup ;;
            2) manage_one_service rclone-internxt ;;
            3) manage_one_service jfms-stack ;;
            "$opt_all")
                local rc=0
                for name in "${names[@]}"; do
                    if svc_exists "$name" || [[ "$name" == jfms-backup || "$name" == jfms-stack ]]; then
                        svc_install "$name" || rc=1
                    fi
                done
                ((rc)) || ok "Alle Services repariert/aktualisiert." ;;
            "$opt_back") return 0 ;;
            *) echo "Ungültig" ;;
        esac
    done
}

# ============================================================
# NEU: Update / Install / Live
# ============================================================
is_installed() { [[ -f "$INSTALL_MENU" ]]; }

self_install() {
    local TMP; TMP=$(mktemp)
    if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
        install -m 0755 "${BASH_SOURCE[0]}" "$INSTALL_MENU"
        rm -f "$TMP"
    else
        curl -fsSL "$SELF_URL" -o "$TMP" || { rm -f "$TMP"; fail "Download fehlgeschlagen: $SELF_URL"; }
        install -m 0755 "$TMP" "$INSTALL_MENU"
        rm -f "$TMP"
    fi
    install_subscripts
    ok "Installiert: $INSTALL_MENU"
}

# NEU: Live-Modus - lädt die aktuelle GitHub-Version und führt sie aus,
# ohne die installierte Datei zu ersetzen.
run_live() {
    [[ -n "$SELF_URL" && "$SELF_URL" != *"<user>"* ]] || fail "SELF_URL nicht konfiguriert."
    info "Lade aktuelle Version live von: $SELF_URL"
    local TMP; TMP=$(mktemp)
    curl -fsSL "$SELF_URL" -o "$TMP" || { rm -f "$TMP"; fail "Download fehlgeschlagen."; }
    chmod 0755 "$TMP"
    # install_subscripts wird vom geladenen Skript selbst aufgerufen
    exec bash "$TMP" --live-exec
}

# NEU: Update prüfen (wenn installiert)
check_update_available() {
    [[ -z "$SELF_URL" || "$SELF_URL" == *"<user>"* ]] && return 2
    local TMP; TMP=$(mktemp)
    if ! curl -fsSL --max-time 10 "$SELF_URL" -o "$TMP" 2>/dev/null; then
        rm -f "$TMP"; return 2
    fi
    if cmp -s "$TMP" "$INSTALL_MENU"; then rm -f "$TMP"; return 1
    else rm -f "$TMP"; return 0
    fi
}
do_update() {
    section "Update-Prüfung"
    echo "Lokale Version: $VERSION"
    echo "Remote:         $SELF_URL"
    if [[ "$SELF_URL" == *"<user>"* ]]; then
        warn "SELF_URL ist nicht konfiguriert."
        return 1
    fi
    check_update_available
    case $? in
        0)
            info "Update verfügbar. Lade und starte Installation..."
            curl -fsSL "$SELF_URL" | sudo bash -- --install
            ok "Update abgeschlossen."
            exit 0 ;;
        1) ok "Bereits aktuell ($VERSION)." ;;
        *) warn "Update-Prüfung nicht möglich." ;;
    esac
}

# ============================================================
# Sub-Skripte
# ============================================================
emit_script() {
    local OUT=$1 MAIN=$2; shift 2
    {
        echo '#!/usr/bin/env bash'
        echo 'set -Eeuo pipefail'
        local FN
        for FN in "$@"; do declare -f "$FN" || fail "Funktion fehlt: $FN"; done
        echo "$MAIN \"\$@\""
    } > "$OUT"
    chmod 0755 "$OUT"
}
install_subscripts() {
    emit_script "$INSTALL_RCLONE" rclone_main \
        fail ok info warn section step version_ok rclone_healthy rclone_main
    emit_script "$INSTALL_JFMS" jellyfin_main \
        fail ok info warn section step \
        docker_works install_docker prompt_value prompt_secret \
        jellyfin_main
    emit_script "$INSTALL_BACKUP" backup_main backup_main
}

# ============================================================
# NEU: Hauptmenü mit Live/Install je Modus
# ============================================================
main_menu() {
    [[ $EUID -eq 0 ]] || fail "Bitte mit sudo/root ausführen."
    local mode_label
    if is_installed; then mode_label="installiert"; else mode_label="LIVE"; fi
    while true; do
        echo
        echo "=== JFMS Verwaltung ($VERSION) [$mode_label] ==="
        echo
        if [[ "$mode_label" == "LIVE" ]]; then
            echo "1) Lokal installieren (dauerhaft einrichten)"
        else
            echo "1) Update prüfen / neu installieren"
        fi
        echo "2) Backup jetzt erstellen"
        echo "3) Backup wiederherstellen"
        echo "4) Neuestes Backup anzeigen"
        echo "5) Services verwalten (install/config/uninstall/status)"
        echo "6) rclone/Internxt Setup ausführen"
        echo "7) JFMS Setup ausführen (Jellyfin Stack)"
        echo "8) Live-Modus ausführen (frische Version von GitHub)"
        echo "9) Beenden"
        local C; read -r -p "Auswahl [9]: " C || exit 0
        case "${C:-9}" in
            1)
                if [[ "$mode_label" == "LIVE" ]]; then
                    self_install
                    exec "$INSTALL_MENU" "$@"
                else
                    do_update
                fi ;;
            2) backup_main     || true ;;
            3) restore_main    || true ;;
            4) show_latest     || true ;;
            5) manage_services || true ;;
            6) "$INSTALL_RCLONE" || true ;;
            7) "$INSTALL_JFMS"   || true ;;
            8) run_live ;;
            9) exit 0 ;;
            *) echo "Ungültig" ;;
        esac
    done
}

# ============================================================
# NEU: Einstieg mit --install / --live / --live-exec / --backup-only
# ============================================================
case "${1:-}" in
    --backup-only) backup_main; exit $? ;;
    --install)     self_install; exec "$INSTALL_MENU" "${@:2}" ;;
    --live)        run_live ;;
    --live-exec)   # interner Modus: wir wurden von run_live gestartet
                   install_subscripts
                   main_menu "${@:2}" ;;
esac

# Standardverhalten:
# - wenn über /usr/local/sbin/jfms gestartet: installiertes Menü
# - sonst (curl | bash oder /tmp/jfms3.sh): LIVE ohne Installation des Menü-Skripts
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || echo "")"
if [[ "$SELF_PATH" == "$INSTALL_MENU" ]]; then
    install_subscripts
    main_menu "$@"
else
    info "Live-Modus: Menü-Skript wird NICHT installiert (Punkt 1 zum Installieren)."
    install_subscripts
    main_menu "$@"
fi
