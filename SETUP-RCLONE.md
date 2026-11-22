# Setup – rclone NFS (Media Mount)

Dieses Dokument beschreibt die Einbindung der Internxt-Cloud als NFS-Mount nach `/mnt/internxt`.
**Überspringe dieses Setup**, wenn du bereits ein anderes Netzwerk-Laufwerk (SMB, anderes NFS, lokal) unter `/mnt/internxt` eingebunden hast.

## 1. Voraussetzungen
- Der aktuelle Benutzer (`$USER`) hat ein funktionierendes rclone-Remote namens `internxt:media`.
- Die rclone-Config liegt unter `/home/$USER/.config/rclone/rclone.conf`.

## 2. Pakete installieren
```bash
sudo apt update
sudo apt install -y nfs-common rclone curl
```

## 3. rclone-Config systemweit bereitstellen
```bash
sudo mkdir -p /etc/rclone
sudo install -o $USER -g $USER -m 640 /home/$USER/.config/rclone/rclone.conf /etc/rclone/rclone.conf
sudo chown $USER:$USER /etc/rclone
sudo chmod 750 /etc/rclone
```

## 4. rclone Service installieren
```bash
# Service-Dateien aus dem Repo beziehen
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/rclone.service -o /etc/systemd/system/rclone.service
sudo mkdir -p /etc/systemd/system/rclone.service.d
sudo curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/src/rclone/override.conf -o /etc/systemd/system/rclone.service.d/override.conf

# User in der Service-Datei auf den aktuellen Benutzer anpassen
sudo sed -i "s/User=tcsoc/User=$USER/g" /etc/systemd/system/rclone.service
sudo sed -i "s/Group=tcsoc/Group=$USER/g" /etc/systemd/system/rclone.service

# Service starten
sudo systemctl daemon-reload
sudo systemctl enable --now rclone.service
```

## 5. NFS mounten
```bash
sudo mkdir -p /mnt/internxt
sudo mount -t nfs -o port=2049,mountport=2049,tcp,nfsvers=3 127.0.0.1:/ /mnt/internxt
```

## 6. Persistenten Mount einrichten (Reboot-fest)
```bash
echo '127.0.0.1:/ /mnt/internxt nfs port=2049,mountport=2049,tcp,nfsvers=3,hard,timeo=600,retrans=2,_netdev,noauto,x-systemd.automount 0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
```
