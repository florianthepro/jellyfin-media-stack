# JFMS – Jellyfin Media Stack

Stack: Jellyfin · Tdarr · IPTV-EPG · Portainer · Cloudflared · Backup
Storage: Internxt via rclone NFS (`127.0.0.1:2049`)

---

## Voraussetzungen

```bash
sudo apt update
sudo apt install -y nfs-common rclone docker.io docker-compose-plugin
```

- User `tcsoc` mit funktionierendem rclone-Remote `internxt:media`
- `.env` vorhanden (siehe `beispiel.env`)

---

## Dateien im Repo

```
compose.yaml
beispiel.env        → als .env kopieren
config/backup/backup.sh
config/backup/entrypoint.sh
```

---

## `.env` Format

```env
NAME=jellyfin-media-stack
PUID=1000
PGID=1000
TZ=Europe/Berlin
MEDIA=/mnt/internxt
IPTV_CHANNELS_XML=./config/iptv-epg/channels.xml
TDARR_API_KEY=
CLOUDFLARE_API_KEY=
BACKUP_DIR=/mnt/internxt/backup
RCLONE_CONF_DIR=/home/tcsoc/.config/rclone
```

---

## Installation (einmalig, in dieser Reihenfolge)

### 1. rclone-Remote einrichten (User `tcsoc`)
```bash
rclone config
rclone lsd internxt:media
```

### 2. Config für Dienst zugänglich machen
```bash
sudo mkdir -p /etc/rclone
sudo install -o tcsoc -g tcsoc -m 640 \
  /home/tcsoc/.config/rclone/rclone.conf /etc/rclone/rclone.conf
sudo chown tcsoc:tcsoc /etc/rclone
sudo chmod 750 /etc/rclone
```

### 3. rclone NFS-Service anlegen
```bash
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

### 4. NFS mounten
```bash
sudo mkdir -p /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 \
  127.0.0.1:/ /mnt/internxt
```

### 5. Persistenter Mount (Reboot-fest)
```bash
echo '127.0.0.1:/ /mnt/internxt nfs port=2049,mountport=2049,tcp,nfsvers=3,hard,timeo=600,retrans=2,_netdev,noauto,x-systemd.automount 0 0' \
  | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

### 6. Stack starten
```bash
cd /opt/jfms
sudo docker compose up -d
```

---

## Manuelle Befehle

### Stack
```bash
cd /opt/jfms
sudo docker compose ps
sudo docker compose logs -f jellyfin
sudo docker compose up -d --force-recreate
sudo docker compose down
```

### rclone / NFS
```bash
sudo systemctl status rclone.service
sudo systemctl restart rclone.service
sudo journalctl -u rclone.service -n 50 --no-pager -f
mount | grep /mnt/internxt
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

### Backup
```bash
# Manuell anstoßen
sudo docker compose -f /opt/jfms/compose.yaml exec backup /usr/local/bin/backup.sh

# Log
sudo docker logs jfms-backup --tail 50

# Tars listen
ls -lt /mnt/internxt/backup/*.tar | head

# Tar-Inhalt ansehen
tar -tf "$(ls -t /mnt/internxt/backup/*.tar | head -1)" | head -30

# Einzelne Datei wiederherstellen
mkdir -p /tmp/restore
tar -xf /mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar -C /tmp/restore

# Alte Backups löschen (>30 Tage)
find /mnt/internxt/backup -name 'jfms-config-*.tar' -mtime +30 -delete
```

### Container-Shells
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec jellyfin bash
sudo docker compose -f /opt/jfms/compose.yaml exec tdarr bash
sudo docker compose -f /opt/jfms/compose.yaml exec backup sh
```

### Sichtbarkeit prüfen
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec jellyfin ls -1 /media
sudo docker compose -f /opt/jfms/compose.yaml exec tdarr ls -1 /media
ls -ln /mnt/internxt | head
```

### rclone-Speicher
```bash
sudo -u tcsoc rclone about internxt: --config /etc/rclone/rclone.conf
sudo -u tcsoc rclone lsd internxt:media --config /etc/rclone/rclone.conf
```

### VFS-Cache leeren
```bash
sudo systemctl stop rclone.service
sudo rm -rf /var/cache/rclone-internxt/*
sudo systemctl start rclone.service
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

---

## Backup-Layout

Ziel: `$BACKUP_DIR/jfms-config-YYYYMMDD-HHMMSS.tar`

Inhalt:
```
compose.yaml
.env
config/
rclone/rclone.conf
```

Schedule: täglich 02:00 (crond im Container `jfms-backup`).

---

## Pflicht-Einstellungen in Jellyfin

Nach jedem Neuaufsetzen:

```
1. Bibliotheken anlegen (Pfad: /media/...)
2. Pro Bibliothek: Echtzeitüberwachung DEAKTIVIEREN
   (NFS unterstützt kein inotify → sonst Endlos-Scans + Fehler)
3. Live-TV Aufnahmen: /media/jellyfin/livetv/recordings
```

---

## Bekannte Stolperfallen

| Symptom                                   | Fix                                                                 |
|-------------------------------------------|---------------------------------------------------------------------|
| `permission denied` auf `/etc/rclone/...` | `sudo chown tcsoc:tcsoc /etc/rclone`                                |
| `Protocol not supported` beim Mount        | `nfsvers=3` in `mount -o`                                           |
| `Max space used (status 420)`             | VFS-Cache leeren (siehe oben) + `rclone about` prüfen               |
| Jellyfin sieht leere Ordner               | Echtzeitüberwachung AUS + Bibliothek manuell scannen                |
| `ESTALE` / Stale Handle                   | `--nfs-cache-type=disk` in `rclone.service`                         |
| Dateien gehören falschem User             | `--uid 1000 --gid 1000` in `rclone.service` (nicht im Mount!)      |
| Backup landet lokal statt NFS             | `mount \| grep /mnt/internxt` prüfen vor Backup-Start               |
| `Resource is still in use` bei `down`     | `sudo docker compose down` erneut, dann `sudo umount -l /mnt/internxt` |

---

## Sicherheit

- rclone NFS lauscht **nur** auf `127.0.0.1:2049` – nicht nach außen öffnen
- `.env` enthält API-Keys → `chmod 600 .env`
- Backups enthalten `rclone.conf` mit Tokens → `BACKUP_DIR` schützen
- `/etc/rclone/rclone.conf`: `chmod 640`, `chown tcsoc:tcsoc`
