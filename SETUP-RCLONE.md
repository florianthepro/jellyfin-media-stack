# Setup – rclone NFS (Media Mount)

Dieses Dokument beschreibt die Einbindung der Internxt-Cloud als NFS-Mount nach `/mnt/internxt`.
**Überspringe dieses Setup**, wenn du bereits ein anderes Netzwerk-Laufwerk (SMB, anderes NFS, lokal) unter `/mnt/internxt` eingebunden hast.

## 1. Voraussetzungen
- Der aktuelle Benutzer hat ein funktionierendes rclone-Remote namens `internxt:media`.
- Die rclone-Config liegt unter `~/.config/rclone/rclone.conf`.
- `curl` und `nfs-common` sind installiert (`sudo apt install curl nfs-common`).

## 2. Automatisches Setup

Führe diesen Kettenbefehl als normaler Benutzer aus (er fordert bei Bedarf dein sudo-Passwort an). Er räumt alte Dienste auf, richtet die Konfiguration ein, ersetzt den Benutzer-Platzhalter und mountet das Laufwerk.

```bash
export REAL_USER=${SUDO_USER:-$USER} && \
sudo systemctl stop rclone.service 2>/dev/null || true && \
sudo umount -l /mnt/internxt 2>/dev/null || true && \
sudo pkill -9 -f '[r]clone serve nfs' 2>/dev/null || true && \
sudo mkdir -p /etc/rclone && \
sudo install -o $REAL_USER -g $REAL_USER -m 640 /home/$REAL_USER/.config/rclone/rclone.conf /etc/rclone/rclone.conf && \
sudo chown $REAL_USER:$REAL_USER /etc/rclone && \
sudo chmod 750 /etc/rclone && \
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/rclone.service -o /etc/systemd/system/rclone.service && \
sudo mkdir -p /etc/systemd/system/rclone.service.d && \
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/override.conf -o /etc/systemd/system/rclone.service.d/override.conf && \
sudo sed -i "s/<user>/$REAL_USER/g" /etc/systemd/system/rclone.service && \
sudo systemctl daemon-reload && \
sudo systemctl enable --now rclone.service && \
sleep 4 && \
sudo mkdir -p /mnt/internxt && \
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

*(Der Befehl nutzt `$SUDO_USER`, um sicherzustellen, dass der Dienst unter deinem tatsächlichen Login-Benutzer läuft und nicht unter `root`. Zudem erzwingt `nfsvers=3` das korrekte Protokoll.)*

## 3. Persistenten Mount einrichten (Reboot-fest)

Damit das Laufwerk nach einem Neustart automatisch eingebunden wird, füge folgenden Eintrag zur `/etc/fstab` hinzu:

```bash
echo '127.0.0.1:/ /mnt/internxt nfs port=2049,mountport=2049,tcp,nfsvers=3,hard,timeo=600,retrans=2,_netdev,noauto,x-systemd.automount 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```

## 4. Überprüfung

Prüfe, ob der Dienst läuft und der Mount erfolgreich war:

```bash
systemctl status rclone.service
mount | grep /mnt/internxt
```
