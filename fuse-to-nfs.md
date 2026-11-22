```
sudo bash <<'ROOT'
set -euo pipefail

# ==========================================
# SCHRITT 1: Alten FUSE-Mount stoppen
# ==========================================
echo ">>> Schritt 1: Stoppe alten rclone-FUSE-Mount..."
systemctl stop rclone-internxt.service || true
systemctl disable rclone-internxt.service || true

# ==========================================
# SCHRITT 2: Dienste für NFS anpassen
# ==========================================
echo ">>> Schritt 2: Erstelle neuen NFS-Server-Dienst..."

# --- 2a. Neue systemd-Unit für 'rclone serve nfs' ---
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
# Wichtig: --nfs-cache-type disk verhindert Stale-Handle-Fehler bei Neustarts
# --vfs-cache-mode=full ist für Schreibzugriff (Live-TV) erforderlich.
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

# --- 2b. Die bestehende override.conf für den alten Dienst kann bleiben oder gelöscht werden.
# Wir erstellen eine neue Override-Datei für den NFS-Dienst mit deinen Speicherwerten.
mkdir -p /etc/systemd/system/rclone-nfs-server.service.d
cat > /etc/systemd/system/rclone-nfs-server.service.d/override.conf <<'UNIT'
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
UNIT

# --- 2c. NFS-Client-Paket sicherstellen ---
echo ">>> Stelle sicher, dass nfs-common installiert ist..."
if ! dpkg -s nfs-common &>/dev/null; then
    apt-get update && apt-get install -y nfs-common
fi

# --- 2d. Hinweis zur Jellyfin-Konfiguration ---
echo ">>> WICHTIG: Jellyfin-Echtzeitüberwachung muss deaktiviert werden."
echo "    Gehe im Jellyfin-Dashboard zu: Bibliothek -> [Deine Bibliothek] -> 'Echtzeitüberwachung' deaktivieren."
echo "    Grund: NFS unterstützt inotify nicht zuverlässig, was sonst zu Scan-Fehlern führt."

# ==========================================
# SCHRITT 3: Mount neu einhängen & Dienste starten
# ==========================================
echo ">>> Schritt 3: Starte NFS-Server und hänge den Mount ein..."

# --- 3a. NFS-Server starten ---
systemctl daemon-reload
systemctl reset-failed rclone-nfs-server.service || true
systemctl enable --now rclone-nfs-server.service

# Kurz warten, damit der Server bereit ist
sleep 3

# --- 3b. Neuen Mount-Punkt erstellen und einhängen ---
mkdir -p /mnt/internxt-nfs
# Aushängen, falls noch ein alter Mount existiert
umount /mnt/internxt-nfs 2>/dev/null || true

mount -t nfs -o port=2049,mountport=2049,tcp,vers=3 127.0.0.1:/ /mnt/internxt-nfs

echo ">>> NFS-Mount erfolgreich nach /mnt/internxt-nfs eingehängt."

# ==========================================
# WICHTIG: Pfade in deiner Umgebung anpassen
# ==========================================
echo ""
echo "=========================================="
echo "NÄCHSTE SCHRITTE (manuell):"
echo "1. Passe in deiner compose.yaml / .env den MEDIA-Pfad an:"
echo "   Alt: MEDIA=/mnt/internxt"
echo "   Neu: MEDIA=/mnt/internxt-nfs"
echo ""
echo "2. Passe im Backup-Skript (/usr/local/sbin/jfms-config-backup) den DEST-Pfad an:"
echo "   Alt: DEST=/mnt/internxt/backup"
echo "   Neu: DEST=/mnt/internxt-nfs/backup"
echo ""
echo "3. Deaktiviere die Echtzeitüberwachung in Jellyfin (siehe Hinweis oben)."
echo "=========================================="
ROOT
