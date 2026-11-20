===== rclone-internxt.service ===== /etc/systemd/system/rclone-internxt.service
```
[Unit]
Description=Internxt rclone mount for tcsoc
Wants=network-online.target
After=network-online.target
Before=docker.service
RequiresMountsFor=/mnt

[Service]
Type=notify
User=tcsoc
Group=tcsoc
ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=/home/tcsoc/.config/rclone/rclone.conf --cache-dir=/var/cache/rclone-internxt --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO
ExecStop=/bin/fusermount3 -uz /mnt/internxt
Restart=on-failure
RestartSec=10
TimeoutStartSec=90
TimeoutStopSec=30
KillMode=mixed

[Install]
WantedBy=multi-user.target
```
===== override.conf ===== /etc/systemd/system/rclone-internxt.service.d/override.conf
```
[Service]
MemoryLow=128M
MemoryHigh=512M
MemoryMax=768M
MemorySwapMax=256M
CPUWeight=100
```
===== compose.yaml =====
```
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./config/portainer:/data"
    restart: always
  cloudflared:
    profiles: [always-active]
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    command: ["tunnel", "--no-autoupdate", "run", "--token", "${CLOUDFLARE_API_KEY}"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    restart: always
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    environment: {TZ: "${TZ}"}
    volumes:
      - "./config/jellyfin/config:/config"
      - "./data/jellyfin/cache:/cache"
      - "${MEDIA}:/media:ro"
      - "${MEDIA}/jellyfin/livetv/recordings:/media/jellyfin/livetv/recordings:rw"
    restart: unless-stopped
  tdarr:
    image: ghcr.io/haveagitgat/tdarr:latest
    container_name: tdarr
    environment: {TZ: "${TZ}", PUID: "${PUID}", PGID: "${PGID}", serverIP: "0.0.0.0", serverPort: "8266", webUIPort: "8265", internalNode: "true", inContainer: "true", auth: "true", apiKey: "${TDARR_API_KEY}"}
    cpus: "0.7"
    volumes:
      - "./config/tdarr/server:/app/server"
      - "./config/tdarr/configs:/app/configs"
      - "./data/tdarr/logs:/app/logs"
      - "./data/tdarr/temp:/temp"
      - "${MEDIA}:/media:ro"
      - "${MEDIA}/tdarr:/media/tdarr:rw"
    restart: unless-stopped
  iptv-epg:
    image: ghcr.io/iptv-org/epg:master
    container_name: iptv-epg
    environment: {TZ: "${TZ}", CRON_SCHEDULE: "30 2 * * *", DAYS: "7", RUN_AT_STARTUP: "true"}
    volumes:
      - "./data/iptv-epg/public:/epg/public"
      - "./config/iptv-epg/channels.xml:/epg/public/channels.xml:ro"
    restart: unless-stopped
```
===== .env =====
```
NAME=jellyfin-media-stack
PUID=1000
PGID=1000
TZ=Europe/Berlin
MEDIA=/mnt/internxt
IPTV_CHANNELS_XML=/mnt/internxt/jellyfin/livetv/channels/all/channels.xml
TDARR_API_KEY=
CLOUDFLARE_API_KEY=
```
===== backup =====
```
sudo bash <<'ROOT'
set -euo pipefail

cat > /usr/local/sbin/jfms-config-backup <<'SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

SRC=/opt/jfms
MOUNT=/mnt/internxt
DEST="$MOUNT/backup"

exec 9>/run/lock/jfms-config-backup.lock
flock -n 9 || { echo "Backup läuft bereits." >&2; exit 1; }

mountpoint -q "$MOUNT" || { echo "FEHLER: $MOUNT ist nicht eingehängt" >&2; exit 1; }
[[ -d "$SRC/config" ]] || { echo "FEHLER: $SRC/config fehlt" >&2; exit 1; }
[[ -f "$SRC/compose.yaml" ]] || { echo "FEHLER: $SRC/compose.yaml fehlt" >&2; exit 1; }

mkdir -p "$DEST"
umask 077

stamp=$(date +%Y%m%d-%H%M%S)
out="$DEST/jfms-config-$stamp.tar"
n=1
while [[ -e "$out" ]]; do
  n=$((n + 1))
  out="$DEST/jfms-config-$stamp-v$n.tar"
done

tmp=$(mktemp "$DEST/.jfms-config-$stamp.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT

tar --numeric-owner --acls --xattrs -cpf "$tmp" -C "$SRC" config compose.yaml
tar -tf "$tmp" >/dev/null
mv -- "$tmp" "$out"
trap - EXIT

echo "Backup erstellt: $out"
SCRIPT

chmod 0755 /usr/local/sbin/jfms-config-backup

cat > /etc/systemd/system/jfms-config-backup.service <<'UNIT'
[Unit]
Description=JFMS-Konfigurationsbackup nach Internxt
Requires=rclone-internxt.service
After=rclone-internxt.service

[Service]
Type=oneshot
User=tcsoc
Group=tcsoc
UMask=0077
ExecStart=/usr/local/sbin/jfms-config-backup
TimeoutStartSec=20min
UNIT

cat > /etc/systemd/system/jfms-config-backup.timer <<'UNIT'
[Unit]
Description=Tägliches JFMS-Konfigurationsbackup um 02:00

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
Unit=jfms-config-backup.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now jfms-config-backup.timer
ROOT
