#!/usr/bin/env bash
set -Eeuo pipefail

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

fail() {
    echo
    echo "FEHLER: $*" >&2
    exit 1
}

step() {
    echo
    echo "=== $* ==="
}

healthy() {
    timeout 5 systemctl is-active --quiet "$N" &&
        timeout 5 mountpoint -q "$M" &&
        timeout --kill-after=2 8 sudo -u "$U" -H ls -U "$M" >/dev/null 2>&1
}

step "4/6 MOUNT PRÜFEN"
if healthy; then
    echo "Mount: gesund, kein Neustart"
else
    step "5/6 MOUNT REPARIEREN"
    timeout --kill-after=10 120 systemctl stop "$N" >/dev/null 2>&1 || true
    mapfile -t P < <(pgrep -f "^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)" || true)

    if ((${#P[@]})); then
        kill -TERM "${P[@]}" 2>/dev/null || true
        sleep 5
        for I in "${P[@]}"; do
            kill -0 "$I" 2>/dev/null && kill -KILL "$I" 2>/dev/null || true
        done
    fi

    timeout 20 fusermount3 -uz "$M" 2>/dev/null ||
        timeout 20 umount -fl "$M" 2>/dev/null || true
    sleep 3
    findmnt --mountpoint "$M" >/dev/null 2>&1 && {
        timeout 20 umount -fl "$M" 2>/dev/null || true
        sleep 3
    }
    findmnt --mountpoint "$M" >/dev/null 2>&1 &&
        fail "Alter FUSE-Mount weiterhin registriert"
    rm -rf "$M"
    install -d -o "$U" -g "$G" -m 0775 "$M"
    install -d -o "$U" -g "$G" -m 0750 "$V"
    echo "Starte Dienst"
    systemctl start "$N" >/dev/null 2>&1 || {
        journalctl -u "$N" -n 40 --no-pager -o cat
        fail "Dienststart fehlgeschlagen"
    }

    K=0
    for I in $(seq 1 60); do
        if healthy; then
            K=1
            break
        fi
        if systemctl is-failed --quiet "$N"; then
            journalctl -u "$N" -n 40 --no-pager -o cat
            fail "Dienst fehlgeschlagen"
        fi
        printf "\rWarte: %3d/120 Sekunden" "$((I*2))"
        sleep 2
    done

    echo
    test "$K" -eq 1 || {
        journalctl -u "$N" -n 40 --no-pager -o cat
        fail "Mount nicht erreichbar"
    }
    echo "Mount: repariert"
fi

step "6/6 ERGEBNIS"
healthy || fail "Abschlussprüfung fehlgeschlagen"
echo "Status:   ERFOLG"
echo "rclone:   $(rclone version | head -1)"
echo "Benutzer: $U"
findmnt --mountpoint "$M" -o TARGET,SOURCE,FSTYPE,OPTIONS
echo
timeout 10 sudo -u "$U" -H ls -Ula "$M" | head -20
echo
echo "Docker und andere Projekte wurden nicht neu gestartet."
