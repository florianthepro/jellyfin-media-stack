> [!IMPORTANT]
> **Für die Einbindung der Medien via rclone (Internxt) siehe [SETUP-RCLONE.md](./SETUP-RCLONE.md).**
> 
> (Oder ein anderes Netzwerk-Laufwerk unter `/mnt/internxt` einbinden).

> [!TIP]
> System: frisches Debian-System wird vorausgesetzt

> [!NOTE]
> Dieses README beschreibt die Einrichtung des Docker-Stacks, die Jellyfin-Einstellungen und die Wartung.

# JFMS – Jellyfin Media Stack

Stack: Jellyfin · Tdarr · IPTV-EPG · Portainer · Cloudflared · Backup  
Storage: Externer Mount unter `/mnt/internxt`

---

<!--
## Architektur & Design-Entscheidungen

- `/media`-Verzeichnis ist read-only (`:ro`)
- `/media/jellyfin/livetv/` und `/media/tdarr/` sind read-write (`:rw`)
- rclone-Config (falls genutzt) liegt unter `/etc/rclone/rclone.conf`

---

-->
## Setup Docker Stack

```bash
echo "Voraussetzungen & Docker installieren:" && sudo apt update && sudo apt install -y curl docker.io docker-compose-plugin micro && sudo systemctl enable --now docker echo "Projektverzeichnis vorbereiten:" && sudo mkdir -p /opt/jfms && sudo chown $USER:$USER /opt/jfms && cd /opt/jfms echo "Docker-Konfiguration beziehen:" && echo "===== Compose-Datei und Beispiel-.env herunterladen =====" && curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/docker/compose.yaml -o /opt/jfms/compose.yaml && curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/docker/beispiel.env -o /opt/jfms/beispiel.env && echo "===== .env aus dem Beispiel erstellen =====" && mv /opt/jfms/beispiel.env /opt/jfms/.env && sudo chmod 600 /opt/jfms/.env
```
.env anpassen
```bash
sudo micro /opt/jfms/.env
```
Trage hier deine API-Keys und den Pfad zur `IPTV_CHANNELS_XML` ein. (Wenn erfordlich `PUID`, `PGID`und `TZ` anpassen.)
*Hinweis: Der Pfad für `MEDIA` steht standardmäßig auf `/mnt/internxt`. Wenn du ein anderes Laufwerk nutzt, passe ihn hier an.*

Stack starten:

```bash
cd /opt/jfms && sudo docker compose up -d
```

---

## Wichtige Einstellungen in Jellyfin

### Echtzeitüberwachung deaktivieren
Wenn ein Netzwerk-Mount (NFS/SMB) genutzt wird, **muss** die Echtzeitüberwachung deaktiviert werden, da sonst Endlos-Scans und massive Log-Fehler auftreten:
```
Dashboard → Bibliothek → [Bibliothek] → Echtzeitüberwachung AUS
```
*(Gilt für jede Bibliothek einzeln).*

### M3U-Tuner (Workaround)
Da `/media` read-only ist, kann Jellyfin M3U-Dateien dort nicht verarbeiten. Der Workaround:
```bash
sudo cp /pfad/zur/channels.m3u /opt/jfms/config/jellyfin/livetv/channels.m3u
```
In Jellyfin als Pfad für den Tuner angeben: `/livetv/channels/channels.m3u`

---

## Manuelle Befehle (Wartung & Fehlerbehebung)

### Backup wiederherstellen

**Schritt 1:** Backup in ein temporäres Verzeichnis entpacken
```bash
# Pfad zum gewünschten Backup anpassen
export BACKUP_FILE=/mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar
sudo rm -rf /tmp/jfms-restore
sudo mkdir -p /tmp/jfms-restore
sudo tar -xf "$BACKUP_FILE" -C /tmp/jfms-restore
```

**Schritt 2:** Kettenbefehl zum Einspielen und Neustart
> [!CAUTION]
> Löscht vorm einspielen alle Container, Netzwerke und Volumes des JFMS-Stacks – auch hängen gebliebene oder unhealthy Container.
```bash
cd /opt/jfms && echo "1. Alle Container des Stacks brutal stoppen und löschen" && sudo docker compose down --remove-orphans || true && sudo docker rm -f $(sudo docker compose ps -aq) 2>/dev/null || true && echo "2. Stack komplett neu bauen und starten" && sudo docker compose up -d --force-recreate && cd /opt/jfms && \
sudo cp -a /tmp/jfms-restore/config/* ./config/ && \
sudo cp -a /tmp/jfms-restore/compose.yaml ./compose.yaml && \
sudo cp -a /tmp/jfms-restore/.env ./.env && \
sudo cp -a /tmp/jfms-restore/rclone/rclone.conf /etc/rclone/rclone.conf && \
sudo chown -R 1000:1000 ./config/jellyfin && \
sudo docker compose up -d --force-recreate
```

### Einzelne Dateien aus einem Backup wiederherstellen
```bash
# Nur eine bestimmte Datei aus dem Tar extrahieren
sudo tar -xf /mnt/internxt/backup/jfms-config-YYYYMMDD-HHMMSS.tar \
  -C /tmp/jfms-restore config/jellyfin/config/system.xml

# Datei an ihren Bestimmungsort kopieren
sudo cp /tmp/jfms-restore/config/jellyfin/config/system.xml \
  /opt/jfms/config/jellyfin/config/system.xml
```

### Manuelles Backup
```bash
echo "Backup manuell starten" && sudo docker compose -f /opt/jfms/compose.yaml exec backup /usr/local/bin/backup.sh && echo "Log prüfen" && sudo docker logs jfms-backup --tail 50 && echo "Backups auflisten" && ls -lt /mnt/internxt/backup/*.tar | head && echo "Prüfen ob rclone.conf im Backup ist" && sudo tar -tf $(ls -t /mnt/internxt/backup/*.tar | head -1) | grep '^rclone/'
```

### rclone / NFS Fehlerbehebung
```bash
echo "Status prüfen" && sudo systemctl status rclone.service && sudo journalctl -u rclone.service -n 50 --no-pager && echo "VFS-Cache leeren (bei "Max space used"-Fehlern)" && sudo systemctl stop rclone.service && sudo rm -rf /var/cache/rclone-internxt/* && sudo systemctl start rclone.service && sudo umount -l /mnt/internxt && sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```
