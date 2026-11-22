# Setup – JFMS (Jellyfin Media Stack)

Dieses Dokument enthält ausschließlich die Schritte zur Ersteinrichtung.
Für Wartung, Fehlerbehebung und manuelle Befehle siehe `README.md`.

## Voraussetzungen

```bash
sudo apt update
sudo apt install -y nfs-common rclone docker.io docker-compose-plugin curl
```

- User `tcsoc` existiert und hat ein funktionierendes rclone-Remote `internxt:media`.
- Zielverzeichnis für den Stack: `/opt/jfms`

## 1. Projektverzeichnis vorbereiten

```bash
sudo mkdir -p /opt/jfms
sudo chown tcsoc:tcsoc /opt/jfms
cd /opt/jfms
```

## 2. Docker-Konfiguration beziehen

```bash
# Compose-Datei
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/docker/compose.yaml \
  -o /opt/jfms/compose.yaml

# Beispiel-.env
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/docker/beispiel.env \
  -o /opt/jfms/beispiel.env

# .env aus Beispiel erstellen
cp /opt/jfms/beispiel.env /opt/jfms/.env
sudo chmod 600 /opt/jfms/.env
```

> **Hinweis:** Passe die Werte in `/opt/jfms/.env` an (insbesondere `PUID`, `PGID`, `TZ` und API-Keys).

## 3. rclone NFS-Service einrichten

```bash
# rclone-Config an einen systemweiten Ort kopieren
sudo mkdir -p /etc/rclone
sudo install -o tcsoc -g tcsoc -m 640 /home/tcsoc/.config/rclone/rclone.conf /etc/rclone/rclone.conf
sudo chown tcsoc:tcsoc /etc/rclone
sudo chmod 750 /etc/rclone

# Service-Dateien aus dem Repo beziehen
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/rclone.service \
  -o /etc/systemd/system/rclone.service

sudo mkdir -p /etc/systemd/system/rclone.service.d
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/override.conf \
  -o /etc/systemd/system/rclone.service.d/override.conf

sudo systemctl daemon-reload
sudo systemctl enable --now rclone.service
```

## 4. NFS mounten

```bash
sudo mkdir -p /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

## 5. Persistenten Mount einrichten (Reboot-fest)

```bash
echo '127.0.0.1:/ /mnt/internxt nfs port=2049,mountport=2049,tcp,nfsvers=3,hard,timeo=600,retrans=2,_netdev,noauto,x-systemd.automount 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

## 6. Stack starten

```bash
cd /opt/jfms
sudo docker compose up -d
```
```

---

## 📄 `README.md`

```markdown
# JFMS – Jellyfin Media Stack

Stack: Jellyfin · Tdarr · IPTV-EPG · Portainer · Cloudflared · Backup  
Storage: Internxt via rclone NFS (`127.0.0.1:2049`)

---

## 1. Einleitung

Dieses Repository stellt einen Docker-Compose-Stack für Jellyfin bereit.
Die Medien liegen auf der Internxt-Cloud und werden über `rclone serve nfs`
als NFS-Mount nach `/mnt/internxt` eingebunden. Ein tägliches Backup der
Konfiguration läuft als eigener Container.

**Wichtige Design-Entscheidungen:**
- `/media` ist im Container **read-only** – nur der Aufnahmeordner
  (`/media/jellyfin/livetv/recordings`) und der Tdarr-Ordner
  (`/media/tdarr`) sind beschreibbar.
- Der NFS-Server läuft lokal auf `127.0.0.1:2049` und ist nicht nach außen
  exponiert.
- Die rclone-Config liegt unter `/etc/rclone/rclone.conf`, damit der
  Dienst sie lesen (und für Token-Refresh schreiben) kann.

Die Ersteinrichtung ist in `setup.md` beschrieben.

---

## 2. Wichtige Einstellungen (Jellyfin & Tdarr)

### 2.1 Jellyfin: Echtzeitüberwachung deaktivieren
```
Dashboard → Bibliothek → [Bibliothek] → Echtzeitüberwachung AUS
```
Gilt für **jede** Bibliothek einzeln. NFS unterstützt kein `inotify`;
andernfalls kommt es zu Endlos-Scans und Log-Fehlern.

### 2.2 Jellyfin: M3U-Tuner (Workaround)
Da `/media` read-only ist, kann Jellyfin M3U-Dateien dort nicht
verarbeiten. Der Workaround:

```bash
sudo cp /pfad/zur/playlist.m3u /opt/jfms/config/jellyfin/playlist.m3u
sudo chown 1000:1000 /opt/jfms/config/jellyfin/playlist.m3u
```

In Jellyfin als Pfad für den Tuner angeben: `/config/playlist.m3u`

### 2.3 Tdarr: Schreibrechte testen
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec tdarr \
  sh -c 'touch /media/tdarr/.w && rm /media/tdarr/.w && echo ok'
```

---

## 3. Manuelle Befehle

### 3.1 Kompletter Force-Reset (Nur dieses Projekt!)
Löscht alle Container, Netzwerke und Volumes des JFMS-Stacks – auch
hängen gebliebene oder unhealthy Container. Andere Host-Projekte
bleiben unberührt.

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
sudo tar -xf /mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar \
  -C /tmp/jfms-restore config/jellyfin/config/system.xml

# Datei an ihren Bestimmungsort kopieren
sudo cp /tmp/jfms-restore/config/jellyfin/config/system.xml \
  /opt/jfms/config/jellyfin/config/system.xml
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

# VFS-Cache leeren (bei "Max space used"-Fehlern)
sudo systemctl stop rclone.service
sudo rm -rf /var/cache/rclone-internxt/*
sudo systemctl start rclone.service
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt

# Speicherplatz auf Internxt prüfen
sudo -u tcsoc rclone about internxt: --config /etc/rclone/rclone.conf
```
