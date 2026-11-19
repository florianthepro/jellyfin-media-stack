#!/usr/bin/env bash
# setup-rclone-mount.sh - Debian, rclone-internxt Mount einrichten
set -euo pipefail

# ---------- 1. Pakete installieren, falls nicht vorhanden ----------
PKGS=(rclone fuse3)
MISSING=()
for p in "${PKGS[@]}"; do
    dpkg -s "$p" &>/dev/null || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
    echo ">> Installiere: ${MISSING[*]}"
    sudo apt-get update
    sudo apt-get install -y "${MISSING[@]}"
fi

# user_allow_other nur setzen, wenn es noch nicht da ist
grep -qx 'user_allow_other' /etc/fuse.conf || echo 'user_allow_other' | sudo tee -a /etc/fuse.conf >/dev/null

# ---------- 2. Systemd-Dateien anlegen ----------
UNIT=/etc/systemd/system/rclone-internxt.service
OVR_DIR=/etc/systemd/system/rclone-internxt.service.d
OVR=$OVR_DIR/override.conf
# === /etc/systemd/system/rclone-internxt.service ===
sudo tee "$UNIT" >/dev/null <<'EOF'
[Unit]
Description=Internxt rclone/debian-matrix mount
Wants=network-online.target
After=network-online.target
Before=docker.service
RequiresMountsFor=/mnt

[Service]
Type=notify
User=tcsoc
Group=tcsoc

ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=/home/tcsoc/.config/rclone/rclone.conf --cache-dir=/var/cache/rclone-internxt --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-poll-interval=15s --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO

ExecStop=/bin/fusermount3 -uz /mnt/internxt

Restart=on-failure
RestartSec=10
TimeoutStartSec=90
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

=== /etc/systemd/system/rclone-internxt.service.d/override.conf ===
sudo mkdir -p "$OVR_DIR"
sudo tee "$OVR" >/dev/null <<'EOF'
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
EOF

sudo chmod 644 "$UNIT" "$OVR"
sudo systemctl daemon-reload

# ---------- 3. Mount sauber (neu) starten ----------
MNT=/mnt/internxt
sudo mkdir -p "$MNT"

echo ">> Stoppe alten Dienst und entferne alte Mounts"
sudo systemctl stop rclone-internxt.service 2>/dev/null || true
if mountpoint -q "$MNT"; then
    fusermount3 -uz "$MNT" || sudo umount -l "$MNT" || true
fi
pkill -f 'rclone mount internxt:media' 2>/dev/null || true
sleep 2

echo ">> Starte Dienst"
sudo systemctl enable --now rclone-internxt.service

# Warten, bis der Mount aktiv ist
for i in $(seq 1 30); do
    mountpoint -q "$MNT" && break
    sleep 1
done
mountpoint -q "$MNT" || { echo "!! Mount fehlgeschlagen"; exit 1; }

# Abhängige Dienste (z. B. docker) neu starten, damit sie den aktuellen Mount sehen
sudo systemctl try-restart docker.service 2>/dev/null || true

echo ">> Mount aktiv:"
findmnt -T "$MNT" -o TARGET,FSTYPE,SOURCE
