#!/bin/sh
set -eu

SRC=/backup-src
DEST=/backup-dest

mkdir -p "$DEST"
umask 077

stamp=$(date +%Y%m%d-%H%M%S)
out="$DEST/jfms-config-$stamp.tar"
n=1
while [ -e "$out" ]; do 
  n=$((n+1))
  out="$DEST/jfms-config-$stamp-v$n.tar"
done

# Packt exakt diese 4 Ziele aus dem gemounteten /backup-src Verzeichnis
tar --numeric-owner --acls --xattrs -cpf "$out" -C "$SRC" \
  compose.yaml .env config rclone

# Testet, ob das Tar-Archiv lesbar ist
tar -tf "$out" >/dev/null

echo "Backup erstellt: $out ($(stat -c%s "$out") bytes, $(tar -tf "$out" | wc -l) Einträge)"
