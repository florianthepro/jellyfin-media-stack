#!/bin/sh
set -eu

# Installiert GNU tar (für ACLs/Xattrs) und Zeitzonen-Daten in Alpine
apk add --no-cache tar tzdata >/dev/null 2>&1

# Crontab für root im Container anlegen (täglich um 02:00 Uhr)
mkdir -p /var/spool/cron/crontabs
echo '0 2 * * * /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1' > /var/spool/cron/crontabs/root
chmod 0600 /var/spool/cron/crontabs/root

# Startet den Cron-Daemon im Vordergrund (PID 1), damit der Container läuft
exec crond -f -l 2
