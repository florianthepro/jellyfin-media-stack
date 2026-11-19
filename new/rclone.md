## Setup

```

```

## Repair

use `sudo remount-internxt`
setup repair:
```
sudo tee /usr/local/sbin/remount-internxt >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

UNIT="rclone-internxt.service"
MNT="/mnt/internxt"
CACHE="/var/cache/rclone-internxt"
USER_NAME="tcsoc"
GROUP_NAME="tcsoc"

echo "=== Internxt-Mount prüfen ==="

if systemctl is-active --quiet "$UNIT" &&
   mountpoint -q "$MNT" &&
   timeout --kill-after=2 8 sudo -u "$USER_NAME" ls -la "$MNT" >/dev/null 2>&1
then
    echo "Mount funktioniert bereits."
    findmnt --mountpoint "$MNT" -o TARGET,SOURCE,FSTYPE,OPTIONS
    exit 0
fi

echo "Mount oder Dienst ist fehlerhaft. Reparatur beginnt."

echo "=== Dienst kontrolliert stoppen ==="

timeout --kill-after=10 120 systemctl stop "$UNIT" 2>/dev/null || true

echo "=== Verwaiste rclone-Prozesse beenden ==="

mapfile -t PIDS < <(
    pgrep -f '^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)' ||
    true
)

if test "${#PIDS[@]}" -gt 0; then
    kill -TERM "${PIDS[@]}" 2>/dev/null || true
    sleep 5

    for PID in "${PIDS[@]}"; do
        if kill -0 "$PID" 2>/dev/null; then
            kill -KILL "$PID" 2>/dev/null || true
        fi
    done
fi

echo "=== Alten oder defekten FUSE-Mount lösen ==="

if mountpoint -q "$MNT" ||
   findmnt --mountpoint "$MNT" >/dev/null 2>&1 ||
   timeout 3 stat "$MNT" >/dev/null 2>&1
then
    timeout 20 fusermount3 -uz "$MNT" 2>/dev/null ||
    timeout 20 umount -fl "$MNT" 2>/dev/null ||
    true
fi

sleep 3

if findmnt --mountpoint "$MNT" >/dev/null 2>&1; then
    echo "Erster Unmount war nicht erfolgreich. Wiederhole Lazy-Unmount."

    timeout 20 umount -fl "$MNT" 2>/dev/null || true
    sleep 3
fi

if findmnt --mountpoint "$MNT" >/dev/null 2>&1; then
    echo "FEHLER: Der alte FUSE-Mount ist weiterhin registriert."
    findmnt --mountpoint "$MNT" -o TARGET,SOURCE,FSTYPE,OPTIONS
    echo "Ein Serverneustart kann erforderlich sein."
    exit 1
fi

echo "=== Mountpunkt und Cache vorbereiten ==="

rm -rf "$MNT"

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

echo "=== rclone-Dienst starten ==="

systemctl daemon-reload
systemctl reset-failed "$UNIT" 2>/dev/null || true
systemctl enable "$UNIT" >/dev/null
systemctl start "$UNIT"

echo "=== Auf Mount warten ==="

OK=0

for TRY in $(seq 1 60); do
    if mountpoint -q "$MNT" &&
       timeout --kill-after=2 8 \
           sudo -u "$USER_NAME" ls -la "$MNT" >/dev/null 2>&1
    then
        OK=1
        break
    fi

    if systemctl is-failed --quiet "$UNIT"; then
        echo "FEHLER: $UNIT ist fehlgeschlagen."
        journalctl -u "$UNIT" -n 100 --no-pager -o cat
        exit 1
    fi

    sleep 2
done

if test "$OK" -ne 1; then
    echo "FEHLER: Internxt ist nach 120 Sekunden nicht erreichbar."
    journalctl -u "$UNIT" -n 100 --no-pager -o cat
    exit 1
fi

echo
echo "=== Mount erfolgreich repariert ==="

findmnt --mountpoint "$MNT" \
    -o TARGET,SOURCE,FSTYPE,OPTIONS

echo
echo "=== Inhalt ==="

sudo -u "$USER_NAME" timeout 10 \
    ls -la "$MNT" |
    head -30

echo
echo "=== Dienststatus ==="

systemctl status "$UNIT" --no-pager -l |
    head -30

echo
echo "Docker wurde nicht neu gestartet."
echo "Vorhandene Docker-Projekte wurden nicht verändert."
SCRIPT

sudo chmod 750 /usr/local/sbin/remount-internxt
sudo chown root:root /usr/local/sbin/remount-internxt
sudo /usr/local/sbin/remount-internxt
```
