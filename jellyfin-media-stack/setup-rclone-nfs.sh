#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# setup-rclone-nfs.sh
# Stoppt rclone-FUSE-Mount, ersetzt ihn durch rclone serve nfs
# und hängt den NFS-Mount neu ein.
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    echo "FEHLER: Dieses Skript muss als root ausgeführt werden." >&2
    exit 1
fi

echo ">>> Schritt 1: Stoppe alten rclone-FUSE-Mount..."
systemctl stop rclone-internxt.service 2>/dev/null || true
systemctl disable rclone-internxt.service 2>/dev/null || true

# Alten Mount sauber lösen, falls noch vorhanden
if mountpoint -q /mnt/internxt; then
    fusermount3 -uz /mnt/internxt 2>/dev/null || umount -l /mnt/internxt 2>/dev/null || true
fi

echo ">>> Schritt 2: Erstelle neuen NFS-Server-Dienst..."

cat > /etc/systemd/system/rclone-nfs-server.service <<'UNIT'
[Unit]
Description=Internxt rclone NFS Server (ersetzt FUSE-Mount)
Wants=network-online.target
After=network-online.target
Before=docker.service

[Service]
Type=simple
User=tcsoc
Group=tcsoc
ExecStart=/usr/bin/rclone serve nfs internxt:media \
  --config=/home/tcsoc/.config/rclone/rclone.conf \
  --addr 127.0.0.1:2049 \
  --vfs-cache-mode=full \
  --vfs-cache-max-age=5m \
  --vfs-cache-max-size=5G \
  --cache-dir=/var/cache/rclone-internxt \
  --nfs-cache-type=disk \
  --log-level=INFO
Restart=on-failure
RestartSec=10
TimeoutStartSec=90
TimeoutStopSec=30
KillMode=mixed

[Install]
WantedBy=multi-user.target
UNIT

mkdir -p /etc/systemd/system/rclone-nfs-server.service.d
cat > /etc/systemd/system/rclone-nfs-server.service.d/override.conf <<'UNIT'
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
UNIT

echo ">>> Stelle sicher, dass nfs-common installiert ist..."
if ! dpkg -s nfs-common &>/dev/null; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common
fi

echo ">>> Schritt 3: Starte NFS-Server und hänge den Mount ein..."

systemctl daemon-reload
systemctl reset-failed rclone-nfs-server.service 2>/dev/null || true
systemctl enable --now rclone-nfs-server.service

# Warten, bis der NFS-Server lauscht (max. 30s)
for i in $(seq 1 30); do
    if ss -ltn 2>/dev/null | grep -q ':2049 '; then
        break
    fi
    sleep 1
done

mkdir -p /mnt/internxt-nfs
umount /mnt/internxt-nfs 2>/dev/null || true

mount -t nfs -o port=2049,mountport=2049,tcp,vers=3 127.0.0.1:/ /mnt/internxt-nfs

if mountpoint -q /mnt/internxt-nfs; then
    echo ">>> NFS-Mount erfolgreich nach /mnt/internxt-nfs eingehängt."
else
    echo "FEHLER: NFS-Mount konnte nicht eingehängt werden." >&2
    exit 1
fi

# Optional: fstab-Eintrag für persistenten Mount (Kommentar zum Aktivieren)
# grep -q '^127.0.0.1:/ /mnt/internxt-nfs' /etc/fstab || \
#   echo '127.0.0.1:/ /mnt/internxt-nfs nfs port=2049,mountport=2049,tcp,vers=3,_netdev,noauto,x-systemd.automount 0 0' >> /etc/fstab

echo ""
echo "=========================================="
echo "FERTIG. Manuelle Nacharbeiten:"
echo "1. .env / compose.yaml: MEDIA=/mnt/internxt-nfs setzen"
echo "2. /usr/local/sbin/jfms-config-backup: DEST=/mnt/internxt-nfs/backup"
echo "3. Jellyfin: Echtzeitüberwachung für die NFS-Bibliothek deaktivieren"
echo "4. Danach: docker compose up -d --force-recreate"
echo "=========================================="
