# JFMS – Jellyfin Media Stack

Stack: Jellyfin · Tdarr · IPTV-EPG · Portainer · Cloudflared · Backup  
Storage: Internxt via rclone NFS (`127.0.0.1:2049`)

---

## 1. Setup

### 1.1 `.env` vorbereiten
```bash
cp beispiel.env .env
sudo chmod 600 .env
```

### 1.2 rclone NFS-Service anlegen
```bash
sudo mkdir -p /etc/rclone
sudo install -o tcsoc -g tcsoc -m 640 /home/tcsoc/.config/rclone/rclone.conf /etc/rclone/rclone.conf
sudo chown tcsoc:tcsoc /etc/rclone && sudo chmod 750 /etc/rclone

sudo tee /etc/systemd/system/rclone.service >/dev/null <<'UNIT'
[Unit]
Description=Internxt rclone NFS Server
Wants=network-online.target
After=network-online.target
Before=docker.service

[Service]
Type=simple
User=tcsoc
Group=tcsoc
ExecStart=/usr/bin/rclone serve nfs internxt:media \
  --config=/etc/rclone/rclone.conf \
  --addr 127.0.0.1:2049 \
  --uid 1000 --gid 1000 --umask 002 \
  --cache-dir=/var/cache/rclone-internxt \
  --vfs-cache-mode=full \
  --vfs-cache-max-age=5m \
  --vfs-cache-max-size=5G \
  --dir-cache-time=1m \
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

sudo mkdir -p /etc/systemd/system/rclone.service.d
sudo tee /etc/systemd/system/rclone.service.d/override.conf >/dev/null <<'UNIT'
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now rclone.service
```

### 1.3 NFS mounten
```bash
sudo mkdir -p /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

### 1.4 Persistenten Mount einrichten (Reboot-fest)
```bash
echo '127.0.0.1:/ /mnt/internxt nfs port=2049,mountport=2049,tcp,nfsvers=3,hard,timeo=600,retrans=2,_netdev,noauto,x-systemd.automount 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

### 1.5 Stack starten
```bash
cd /opt/jfms
sudo docker compose up -d
```

---

## 2. Wichtige Einstellungen (Jellyfin & Tdarr)

### 2.1 Jellyfin: Echtzeitüberwachung AUS
```
Dashboard → Bibliothek → [Bibliothek] → Echtzeitüberwachung deaktivieren
```
*(Gilt für jede Bibliothek einzeln. NFS unterstützt kein inotify, sonst kommt es zu Endlos-Scans.)*

### 2.2 Jellyfin: M3U-Tuner (Workaround für NFS)
Da `/media` im Container read-only ist, kann Jellyfin M3U-Dateien dort nicht verarbeiten. Der Workaround:
```bash
# M3U-Datei in das Config-Verzeichnis legen
sudo cp /pfad/zur/playlist.m3u /opt/jfms/config/jellyfin/playlist.m3u
sudo chown 1000:1000 /opt/jfms/config/jellyfin/playlist.m3u
```
In Jellyfin als Pfad für den Tuner angeben: `/config/playlist.m3u`

### 2.3 Tdarr: Rechte testen
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec tdarr sh -c 'touch /media/tdarr/.w && rm /media/tdarr/.w && echo ok'
```

---

## 3. Manuelle Befehle

### 3.1 Kompletter Force-Reset (Nur dieses Projekt!)
Löscht alle Container, Netzwerke und Volumes des JFMS-Stacks, auch wenn sie hängen oder unhealthy sind. **Keine Gefahr für andere Host-Projekte.**

```bash
cd /opt/jfms
# 1. Alle Container des Stacks brutal stoppen und löschen
sudo docker compose down --remove-orphans || true
sudo docker rm -f $(sudo docker compose ps -aq) 2>/dev/null || true

# 2. Stack komplett neu bauen und starten
sudo docker compose up -d --force-recreate
```

### 3.2 Backup wiederherstellen (Restore)
**Schritt 1:** Backup in ein temporäres Verzeichnis entpacken
```bash
# Pfad zum gewünschten Backup anpassen
export BACKUP_FILE=/mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar
sudo rm -rf /tmp/jfms-restore
sudo mkdir -p /tmp/jfms-restore
sudo tar -xf "$BACKUP_FILE" -C /tmp/jfms-restore
```

**Schritt 2:** Kettenbefehl zum Einspielen und Neustart
```bash
cd /opt/jfms && \
sudo cp -a /tmp/jfms-restore/config/* ./config/ && \
sudo cp -a /tmp/jfms-restore/compose.yaml ./compose.yaml && \
sudo cp -a /tmp/jfms-restore/.env ./.env && \
sudo cp -a /tmp/jfms-restore/rclone/rclone.conf /etc/rclone/rclone.conf && \
sudo chown -R 1000:1000 ./config/jellyfin && \
sudo docker compose up -d --force-recreate
```

### 3.3 Einzelne Dateien aus einem Backup wiederherstellen
```bash
# Nur eine bestimmte Datei aus dem Tar extrahieren
sudo tar -xf /mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar -C /tmp/jfms-restore config/jellyfin/config/system.xml

# Datei an ihren Bestimmungsort kopieren
sudo cp /tmp/jfms-restore/config/jellyfin/config/system.xml /opt/jfms/config/jellyfin/config/system.xml
```

### 3.4 Backup manuell anstoßen & prüfen
```bash
# Backup manuell starten
sudo docker compose -f /opt/jfms/compose.yaml exec backup /usr/local/bin/backup.sh

# Log prüfen
sudo docker logs jfms-backup --tail 50

# Backups auflisten
ls -lt /mnt/internxt/backup/*.tar | head

# Prüfen ob rclone.conf im Backup ist
sudo tar -tf $(ls -t /mnt/internxt/backup/*.tar | head -1) | grep '^rclone/'
```

### 3.5 rclone / NFS Fehlerbehebung
```bash
# Status prüfen
sudo systemctl status rclone.service
sudo journalctl -u rclone.service -n 50 --no-pager

# VFS-Cache leeren (bei "Max space used" Fehlern)
sudo systemctl stop rclone.service
sudo rm -rf /var/cache/rclone-internxt/*
sudo systemctl start rclone.service
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt

# Speicherplatz auf Internxt prüfen
sudo -u tcsoc rclone about internxt: --config /etc/rclone/rclone.conf
```