# Setup – Nach dem Deployment

## 1. Jellyfin

### 1.1 Erstanmeldung
```
http://<host>:8096
```

### 1.2 Bibliotheken anlegen
```
Dashboard → Bibliothek → Bibliothek hinzufügen
Medientyp: Filme / Serien / Musik
Ordner: /media/<ordner>
```

### 1.3 Echtzeitüberwachung deaktivieren (Pflicht bei NFS)
```
Dashboard → Bibliothek → [Bibliothek] → Einstellungen
→ "Echtzeitüberwachung aktivieren" AUS
→ Speichern
```
Gilt für **jede** Bibliothek einzeln.

### 1.4 Live-TV Aufnahmen
```
Dashboard → Live TV → Aufnahmen
Aufnahmepfad: /media/jellyfin/livetv/recordings
```

### 1.5 Bibliothek scannen
```
Dashboard → Bibliothek → ⋮ → Bibliothek scannen
```

## 2. Tdarr

### 2.1 Erstanmeldung
```
http://<host>:8265
```

### 2.2 Bibliotheken prüfen
```
Libraries → Source: /media/tdarr (rw)
            Output: /media/tdarr (rw)
```

### 2.3 Schreibtest
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec tdarr \
  sh -c 'touch /media/tdarr/.w && rm /media/tdarr/.w && echo ok'
```

## 3. Backup

### 3.1 Manuell anstoßen
```bash
sudo docker compose -f /opt/jfms/compose.yaml exec backup /usr/local/bin/backup.sh
```

### 3.2 Log prüfen
```bash
sudo docker logs jfms-backup --tail 50
```

### 3.3 Backup-Liste
```bash
ls -lt /mnt/internxt/backup/*.tar | head
```

## 4. rclone / NFS

### 4.1 Status
```bash
sudo systemctl status rclone.service
sudo journalctl -u rclone.service -n 30 --no-pager
```

### 4.2 Mount prüfen
```bash
mount | grep /mnt/internxt
```

### 4.3 Bei Problemen: neu mounten
```bash
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

### 4.4 VFS-Cache leeren (bei Upload-Fehlern)
```bash
sudo systemctl stop rclone.service
sudo rm -rf /var/cache/rclone-internxt/*
sudo systemctl start rclone.service
sudo umount -l /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

### 4.5 rclone-Speicher prüfen
```bash
sudo -u tcsoc rclone about internxt: --config /etc/rclone/rclone.conf
```
```

---
