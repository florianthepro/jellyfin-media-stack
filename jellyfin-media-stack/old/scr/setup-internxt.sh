#!/usr/bin/env bash
set -Eeuo pipefail
clear

U="${SUDO_USER:-$(logname 2>/dev/null || true)}"
test -n "$U" && test "$U" != root || {
    echo "FEHLER: Benutzer nicht erkannt"
    exit 1
}
G="$(id -gn "$U")"
H="$(getent passwd "$U" | cut -d: -f6)"
C="$H/.config/rclone/rclone.conf"
M="/mnt/internxt"
V="/var/cache/rclone-internxt"
N="rclone-internxt.service"
F="/etc/systemd/system/$N"
D="/etc/systemd/system/$N.d"
O="$D/override.conf"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo
    echo "FEHLER: $*" >&2
    exit 1
}

step() {
    echo
    echo "=== $* ==="
}

version_ok() {
    command -v rclone >/dev/null 2>&1 || return 1
    local VSN
    VSN="$(rclone version 2>/dev/null | head -1 | sed -E "s/^rclone v([0-9]+\.[0-9]+\.[0-9]+).*/\1/")"
    test -n "$VSN" || return 1
    dpkg --compare-versions "$VSN" ge "1.73.0"
}

step "INTERNXT SETUP"
echo "Benutzer: $U"
echo "Home:     $H"

step "1/6 VORAUSSETZUNGEN"
X=()
dpkg -s fuse3 >/dev/null 2>&1 || X+=(fuse3)
command -v curl >/dev/null 2>&1 || X+=(curl)
command -v unzip >/dev/null 2>&1 || X+=(unzip)

if ((${#X[@]})); then
    echo "Installiere: ${X[*]}"
    apt-get update -qq
    apt-get install -y -qq "${X[@]}" >/tmp/internxt-apt.log 2>&1 || {
        tail -40 /tmp/internxt-apt.log
        fail "Paketinstallation fehlgeschlagen"
    }
else
    echo "Pakete: OK"
fi

test -e /dev/fuse || fail "/dev/fuse fehlt"

if version_ok; then
    echo "rclone: $(rclone version | head -1), Internxt-kompatibel"
else
    echo "rclone fehlt oder ist älter als v1.73.0, installiere aktuelle Version"
    curl -fsSL https://rclone.org/install.sh -o /tmp/rclone-install.sh ||
        fail "Installer konnte nicht geladen werden"
    bash /tmp/rclone-install.sh >/tmp/rclone-install.log 2>&1 || true
    rm -f /tmp/rclone-install.sh
    version_ok || {
        tail -40 /tmp/rclone-install.log 2>/dev/null || true
        fail "Keine Internxt-kompatible rclone-Version installiert"
    }
    echo "rclone: $(rclone version | head -1), Installation OK"
fi

touch /etc/fuse.conf
grep -qxF user_allow_other /etc/fuse.conf || {
    echo user_allow_other >>/etc/fuse.conf
    echo "FUSE: user_allow_other ergänzt"
}
install -d -o "$U" -g "$G" -m 0700 "$(dirname "$C")"
install -d -o "$U" -g "$G" -m 0750 "$V"

step "2/6 INTERNXT-REMOTE"
if ! test -s "$C" ||
    ! timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null |
        grep -Fxq "internxt:"
then
    echo "Remote internxt: fehlt. Interaktive Einrichtung startet."
    echo "Remote bitte exakt internxt nennen."
    sudo -u "$U" -H rclone --config "$C" config
fi

timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null |
    grep -Fxq "internxt:" || fail "Remote internxt: fehlt"
chown "$U:$G" "$C"
chmod 600 "$C"
echo "Remote internxt: OK"

step "3/6 SYSTEMD"
T="$(mktemp)"
Q="$(mktemp)"
trap 'rm -f "$T" "$Q" /tmp/internxt-apt.log /tmp/rclone-install.log /tmp/internxt-verify.log' EXIT

printf "%s\n" \
    "[Unit]" \
    "Description=Internxt rclone mount for $U" \
    "Wants=network-online.target" \
    "After=network-online.target" \
    "Before=docker.service" \
    "RequiresMountsFor=/mnt" \
    "" \
    "[Service]" \
    "Type=notify" \
    "User=$U" \
    "Group=$G" \
    "ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=$C --cache-dir=$V --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO" \
    "ExecStop=/bin/fusermount3 -uz /mnt/internxt" \
    "Restart=on-failure" \
    "RestartSec=10" \
    "TimeoutStartSec=90" \
    "TimeoutStopSec=30" \
    "KillMode=mixed" \
    "" \
    "[Install]" \
    "WantedBy=multi-user.target" >"$T"

printf "%s\n" \
    "[Service]" \
    "MemoryLow=128M" \
    "MemoryHigh=512M" \
    "MemoryMax=768M" \
    "MemorySwapMax=256M" \
    "CPUWeight=100" >"$Q"

Z=0
if test -f "$F" && cmp -s "$T" "$F"; then
    echo "Dienstdatei: korrekt"
else
    install -o root -g root -m 0644 "$T" "$F"
    Z=1
    echo "Dienstdatei: korrigiert"
fi

install -d -m 0755 "$D"
if test -f "$O" && cmp -s "$Q" "$O"; then
    echo "Ressourcenlimits: korrekt"
else
    install -o root -g root -m 0644 "$Q" "$O"
    Z=1
    echo "Ressourcenlimits: korrigiert"
fi

timeout 15 systemctl daemon-reload || fail "daemon-reload fehlgeschlagen"
timeout 15 systemd-analyze verify "$F" >/tmp/internxt-verify.log 2>&1 || {
    cat /tmp/internxt-verify.log
    fail "Systemd-Konfiguration ungültig"
}
timeout 15 systemctl enable "$N" >/dev/null 2>&1 ||
    fail "Dienst konnte nicht aktiviert werden"
systemctl reset-failed "$N" 2>/dev/null || true

bash "$SCRIPT_DIR/recreate-fuse.sh"
