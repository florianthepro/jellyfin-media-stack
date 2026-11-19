## Setup

```
sudo bash <<'SETUP_INTERNXT'
set -Eeuo pipefail

clear

CURRENT_USER="${SUDO_USER:-}"

if test -z "$CURRENT_USER" || test "$CURRENT_USER" = "root"; then
    CURRENT_USER="$(logname 2>/dev/null || true)"
fi

if test -z "$CURRENT_USER" || test "$CURRENT_USER" = "root"; then
    echo "FEHLER: Der angemeldete Nicht-root-Benutzer konnte nicht ermittelt werden."
    echo "Starte den Befehl aus deinem normalen Benutzerkonto mit sudo."
    exit 1
fi

USER_NAME="$CURRENT_USER"
GROUP_NAME="$(id -gn "$USER_NAME")"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"

REMOTE_NAME="internxt:"
REMOTE_PATH="internxt:media"
MNT="/mnt/internxt"
CONFIG="$USER_HOME/.config/rclone/rclone.conf"
CACHE="/var/cache/rclone-internxt"

UNIT_NAME="rclone-internxt.service"
UNIT="/etc/systemd/system/$UNIT_NAME"
OVR_DIR="/etc/systemd/system/$UNIT_NAME.d"
OVR="$OVR_DIR/override.conf"
REPAIR="/usr/local/sbin/remount-internxt"

fail() {
    echo
    echo "============================================================"
    echo "FEHLER"
    echo "============================================================"
    echo "$*" >&2
    exit 1
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

section "INTERNXT-RCLONE-SETUP"

echo "Benutzer:       $USER_NAME"
echo "Gruppe:         $GROUP_NAME"
echo "Home:           $USER_HOME"
echo "Remote:         $REMOTE_PATH"
echo "Mountpunkt:     $MNT"
echo "Konfiguration:  $CONFIG"
echo "Cache:          $CACHE"

section "1/8 PAKETE UND VORAUSSETZUNGEN PRÜFEN"

id "$USER_NAME" >/dev/null 2>&1 ||
    fail "Der Benutzer $USER_NAME existiert nicht."

test -n "$USER_HOME" && test -d "$USER_HOME" ||
    fail "Das Home-Verzeichnis für $USER_NAME wurde nicht gefunden."

MISSING=()

for PKG in rclone fuse3; do
    if dpkg -s "$PKG" >/dev/null 2>&1; then
        echo "OK: $PKG ist installiert."
    else
        echo "FEHLT: $PKG"
        MISSING+=("$PKG")
    fi
done

if ((${#MISSING[@]})); then
    echo
    echo "Installiere: ${MISSING[*]}"
    apt-get update
    apt-get install -y "${MISSING[@]}"
else
    echo
    echo "Alle benötigten Pakete sind bereits installiert."
fi

test -e /dev/fuse ||
    fail "/dev/fuse fehlt. FUSE ist auf dieser VM nicht verfügbar."

touch /etc/fuse.conf

if grep -qxF 'user_allow_other' /etc/fuse.conf; then
    echo "OK: user_allow_other ist bereits in /etc/fuse.conf gesetzt."
else
    echo 'user_allow_other' >> /etc/fuse.conf
    echo "GEÄNDERT: user_allow_other wurde in /etc/fuse.conf ergänzt."
fi

section "2/8 VERZEICHNISSE UND RECHTE VORBEREITEN"

install -d \
    -o "$USER_NAME" \
    -g "$GROUP_NAME" \
    -m 0700 \
    "$(dirname "$CONFIG")"

install -d \
    -o "$USER_NAME" \
    -g "$GROUP_NAME" \
    -m 0750 \
    "$CACHE"

if ! findmnt --mountpoint "$MNT" >/dev/null 2>&1; then
    if test -e "$MNT" || test -L "$MNT"; then
        rm -rf "$MNT"
    fi

    install -d \
        -o "$USER_NAME" \
        -g "$GROUP_NAME" \
        -m 0775 \
        "$MNT"
fi

echo "OK: Konfigurationsverzeichnis vorbereitet."
echo "OK: Cacheverzeichnis vorbereitet."
echo "OK: Mountpunkt vorbereitet oder bereits aktiv."

section "3/8 INTERNXT-ANMELDUNG PRÜFEN"

REMOTE_EXISTS=0

if test -s "$CONFIG"; then
    if sudo -u "$USER_NAME" -H \
        rclone --config "$CONFIG" listremotes 2>/dev/null |
        grep -Fxq "$REMOTE_NAME"
    then
        REMOTE_EXISTS=1
    fi
fi

if test "$REMOTE_EXISTS" -eq 1; then
    echo "OK: Der Remote $REMOTE_NAME ist bereits eingerichtet."
else
    echo "Der Remote $REMOTE_NAME ist noch nicht eingerichtet."
    echo
    echo "Die interaktive rclone-Konfiguration wird jetzt geöffnet."
    echo "Richte einen Remote mit dem Namen internxt ein."
    echo "E-Mail, Passwort und MFA werden nur durch rclone abgefragt."
    echo "Diese Anmeldedaten stehen nicht in diesem Setup-Skript."
    echo

    sudo -u "$USER_NAME" -H \
        rclone --config "$CONFIG" config
fi

sudo -u "$USER_NAME" -H \
    rclone --config "$CONFIG" listremotes |
    grep -Fxq "$REMOTE_NAME" ||
    fail "Der Remote $REMOTE_NAME wurde nicht eingerichtet."

chown "$USER_NAME:$GROUP_NAME" "$CONFIG"
chmod 600 "$CONFIG"

echo "OK: Remote $REMOTE_NAME ist vorhanden."
echo "OK: $CONFIG gehört $USER_NAME:$GROUP_NAME und hat Modus 600."

section "4/8 SYSTEMD-DIENST SCHREIBEN"

cat > "$UNIT" <<UNIT_EOF
[Unit]
Description=Internxt rclone mount for $USER_NAME
Wants=network-online.target
After=network-online.target
Before=docker.service
RequiresMountsFor=/mnt

[Service]
Type=notify
User=$USER_NAME
Group=$GROUP_NAME
ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=$CONFIG --cache-dir=/var/cache/rclone-internxt --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO
ExecStop=/bin/fusermount3 -uz /mnt/internxt
Restart=on-failure
RestartSec=10
TimeoutStartSec=90
TimeoutStopSec=30
KillMode=mixed

[Install]
WantedBy=multi-user.target
UNIT_EOF

install -d -m 0755 "$OVR_DIR"

cat > "$OVR" <<'OVERRIDE_EOF'
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
OVERRIDE_EOF

chown root:root "$UNIT" "$OVR"
chmod 644 "$UNIT" "$OVR"

systemctl daemon-reload
systemd-analyze verify "$UNIT"
systemctl enable "$UNIT_NAME" >/dev/null
systemctl reset-failed "$UNIT_NAME" 2>/dev/null || true

echo "OK: $UNIT wurde geschrieben."
echo "OK: $OVR wurde geschrieben."
echo "OK: systemd-Konfiguration ist gültig."
echo "OK: $UNIT_NAME ist für den Systemstart aktiviert."

section "5/8 REPARATURBEFEHL INSTALLIEREN"

cat > "$REPAIR" <<'REPAIR_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

clear

UNIT="rclone-internxt.service"
MNT="/mnt/internxt"
CACHE="/var/cache/rclone-internxt"
CONFIG="__CONFIG__"
USER_NAME="__USER__"
GROUP_NAME="__GROUP__"

if (( EUID != 0 )); then
    exec sudo bash "$0" "$@"
fi

fail() {
    echo
    echo "============================================================"
    echo "FEHLER"
    echo "============================================================"
    echo "$*" >&2
    exit 1
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

healthy() {
    systemctl is-active --quiet "$UNIT" &&
    mountpoint -q "$MNT" &&
    findmnt --mountpoint "$MNT" >/dev/null 2>&1 &&
    timeout --kill-after=2 8 \
        sudo -u "$USER_NAME" -H \
        ls -la "$MNT" >/dev/null 2>&1
}

section "INTERNXT-MOUNT PRÜFEN"

echo "Benutzer:    $USER_NAME"
echo "Dienst:      $UNIT"
echo "Mountpunkt:  $MNT"

if healthy; then
    echo
    echo "ERGEBNIS: Der Internxt-Mount funktioniert bereits."
    echo

    findmnt --mountpoint "$MNT" \
        -o TARGET,SOURCE,FSTYPE,OPTIONS

    exit 0
fi

echo
echo "ERGEBNIS: Mount oder Dienst ist fehlerhaft."
echo "Die Reparatur wird gestartet."

test -s "$CONFIG" ||
    fail "rclone-Konfiguration fehlt: $CONFIG"

sudo -u "$USER_NAME" -H \
    rclone --config "$CONFIG" listremotes |
    grep -Fxq 'internxt:' ||
    fail "Der Remote internxt: fehlt in $CONFIG."

section "1/5 DIENST STOPPEN"

timeout --kill-after=10 120 \
    systemctl stop "$UNIT" 2>/dev/null ||
    true

echo "Dienst wurde gestoppt oder war bereits inaktiv."

section "2/5 VERWAISTE RCLONE-PROZESSE BEENDEN"

mapfile -t PIDS < <(
    pgrep -f \
        '^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)' ||
    true
)

if ((${#PIDS[@]})); then
    echo "Gefundene Prozesse: ${PIDS[*]}"

    kill -TERM "${PIDS[@]}" 2>/dev/null || true
    sleep 5

    for PID in "${PIDS[@]}"; do
        if kill -0 "$PID" 2>/dev/null; then
            echo "Beende PID $PID mit SIGKILL."
            kill -KILL "$PID" 2>/dev/null || true
        fi
    done
else
    echo "Keine verwaisten rclone-Prozesse gefunden."
fi

section "3/5 ALTEN FUSE-MOUNT LÖSEN"

if mountpoint -q "$MNT" ||
   findmnt --mountpoint "$MNT" >/dev/null 2>&1
then
    echo "Alter Mount wurde erkannt und wird ausgehängt."

    timeout 20 fusermount3 -uz "$MNT" 2>/dev/null ||
    timeout 20 umount -fl "$MNT" 2>/dev/null ||
    true
else
    echo "Kein separater Mount mehr vorhanden."
fi

sleep 3

if findmnt --mountpoint "$MNT" >/dev/null 2>&1; then
    echo "Erster Unmount war nicht erfolgreich. Lazy-Unmount wird wiederholt."

    timeout 20 umount -fl "$MNT" 2>/dev/null || true
    sleep 3
fi

if findmnt --mountpoint "$MNT" >/dev/null 2>&1; then
    findmnt --mountpoint "$MNT" \
        -o TARGET,SOURCE,FSTYPE,OPTIONS

    fail "Der alte FUSE-Mount ist weiterhin registriert. Ein Neustart kann erforderlich sein."
fi

if test -e "$MNT" || test -L "$MNT"; then
    rm -rf "$MNT"
fi

install -d \
    -o "$USER_NAME" \
    -g "$GROUP_NAME" \
    -m 0775 \
    "$MNT"

install -d \
    -o "$USER_NAME" \
    -g "$GROUP_NAME" \
    -m 0750 \
    "$CACHE"

echo "Mountpunkt und Cache wurden vorbereitet."

section "4/5 RCLONE-DIENST STARTEN"

systemctl daemon-reload
systemctl reset-failed "$UNIT" 2>/dev/null || true
systemctl enable "$UNIT" >/dev/null
systemctl start "$UNIT"

echo "Dienst wurde gestartet. Warte auf den Mount."

OK=0

for TRY in $(seq 1 60); do
    if healthy; then
        OK=1
        break
    fi

    if systemctl is-failed --quiet "$UNIT"; then
        journalctl -u "$UNIT" \
            -n 100 \
            --no-pager \
            -o cat

        fail "$UNIT ist fehlgeschlagen."
    fi

    printf '\rWarte auf Internxt: %3d/120 Sekunden' "$((TRY * 2))"
    sleep 2
done

echo

if test "$OK" -ne 1; then
    journalctl -u "$UNIT" \
        -n 100 \
        --no-pager \
        -o cat

    fail "Internxt ist nach 120 Sekunden nicht erreichbar."
fi

section "5/5 ERGEBNIS"

echo "ERFOLG: Der Internxt-Mount wurde repariert."
echo

findmnt --mountpoint "$MNT" \
    -o TARGET,SOURCE,FSTYPE,OPTIONS

echo
echo "Sichtbare Einträge:"

sudo -u "$USER_NAME" -H \
    timeout 10 ls -la "$MNT" |
    head -30

echo
echo "Dienststatus:"

systemctl status "$UNIT" \
    --no-pager \
    -l |
    head -25

echo
echo "Docker wurde nicht neu gestartet."
echo "Andere Docker-Projekte wurden nicht verändert."
REPAIR_EOF

sed -i \
    -e "s|__USER__|$USER_NAME|g" \
    -e "s|__GROUP__|$GROUP_NAME|g" \
    -e "s|__CONFIG__|$CONFIG|g" \
    "$REPAIR"

chown root:root "$REPAIR"
chmod 750 "$REPAIR"

echo "OK: Reparaturbefehl wurde installiert:"
echo "    sudo remount-internxt"

section "6/8 AKTUELLEN MOUNTZUSTAND PRÜFEN"

MOUNT_OK=0

if systemctl is-active --quiet "$UNIT_NAME" &&
   mountpoint -q "$MNT" &&
   findmnt --mountpoint "$MNT" >/dev/null 2>&1 &&
   timeout --kill-after=2 8 \
       sudo -u "$USER_NAME" -H \
       ls -la "$MNT" >/dev/null 2>&1
then
    MOUNT_OK=1
fi

if test "$MOUNT_OK" -eq 1; then
    echo "OK: Mount und Dienst funktionieren bereits."
    echo "Der laufende Mount wird nicht unterbrochen."
else
    echo "Mount oder Dienst ist nicht gesund."
    echo "Die installierte Reparatur wird jetzt ausgeführt."

    "$REPAIR"
fi

section "7/8 ENDZUSTAND PRÜFEN"

systemctl is-active --quiet "$UNIT_NAME" ||
    fail "$UNIT_NAME ist nicht aktiv."

mountpoint -q "$MNT" ||
    fail "$MNT ist kein aktiver Mountpunkt."

findmnt --mountpoint "$MNT" >/dev/null 2>&1 ||
    fail "$MNT ist nicht als eigener Mount registriert."

timeout --kill-after=2 10 \
    sudo -u "$USER_NAME" -H \
    ls -la "$MNT" >/dev/null ||
    fail "$MNT ist für $USER_NAME nicht erreichbar."

echo "OK: systemd-Dienst ist aktiv."
echo "OK: FUSE-Mount ist aktiv."
echo "OK: $USER_NAME kann auf den Mount zugreifen."

section "8/8 ABSCHLUSS"

echo "ERFOLG: Internxt wurde vollständig eingerichtet."
echo
echo "Benutzer:       $USER_NAME"
echo "Gruppe:         $GROUP_NAME"
echo "Remote:         $REMOTE_PATH"
echo "Mountpunkt:     $MNT"
echo "Konfiguration:  $CONFIG"
echo "Cache:          $CACHE"
echo "Dienst:         $UNIT_NAME"
echo "Reparatur:      sudo remount-internxt"
echo

findmnt --mountpoint "$MNT" \
    -o TARGET,SOURCE,FSTYPE,OPTIONS

echo
echo "Sichtbare Einträge:"

sudo -u "$USER_NAME" -H \
    timeout 10 ls -la "$MNT" |
    head -30

echo
echo "Docker und andere Projekte wurden nicht neu gestartet."
SETUP_INTERNXT
```
