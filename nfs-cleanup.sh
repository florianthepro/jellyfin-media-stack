#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# setup-rclone-nfs-v2.sh
# - Mountet NFS wieder 1:1 an /mnt/internxt (wie alter FUSE-Mount)
# - Wärmt rclone-Dir-Cache auf, damit Jellyfin alle Ordner sieht
# - Verifiziert Pfad-Struktur gegen Remote
# - Recreated alle Compose-Services außer cloudflared
# ============================================================

[[ "${EUID}" -eq 0 ]] || { echo "FEHLER: root erforderlich." >&2; exit 1; }

COMPOSE_DIR="${COMPOSE_DIR:-/opt/jfms}"
RCLONE_CONFIG="/home/tcsoc/.config/rclone/rclone.conf"
RCLONE_REMOTE="internxt:media"
MOUNT_PATH="/mnt/internxt"
LEGACY_PATH="/mnt/internxt-nfs"

log()  { printf '\033[1;34m>>> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------
# SCHRITT 1: Container stoppen (verhindert I/O auf hängendem Mount)
# ------------------------------------------------------------
log "Schritt 1: Stoppe Compose-Services (außer cloudflared)..."
cd "$COMPOSE_DIR"

mapfile -t SERVICES < <(docker compose config --services | grep -vx 'cloudflared' || true)
if [[ ${#SERVICES[@]} -eq 0 ]]; then
    fail "Keine Services gefunden in $COMPOSE_DIR"
fi
echo "   Services: ${SERVICES[*]}"
docker compose stop "${SERVICES[@]}" 2>/dev/null || true
ok "Container gestoppt"

# ------------------------------------------------------------
# SCHRITT 2: NFS-Unit auf konsistente Parameter prüfen
# ------------------------------------------------------------
log "Schritt 2: Prüfe rclone-nfs-server.service..."
UNIT=/etc/systemd/system/rclone-nfs-server.service
[[ -f "$UNIT" ]] || fail "$UNIT nicht gefunden – bitte v1-Skript zuerst ausführen."

# --dir-cache-time=1m sicherstellen (wie im alten FUSE-Mount)
if ! grep -q -- '--dir-cache-time' "$UNIT"; then
    sed -i 's|--log-level=INFO|--dir-cache-time=1m --log-level=INFO|' "$UNIT"
    systemctl daemon-reload
    ok "--dir-cache-time=1m ergänzt"
else
    ok "--dir-cache-time bereits gesetzt"
fi

systemctl restart rclone-nfs-server.service
for i in $(seq 1 60); do
    ss -ltn 2>/dev/null | grep -q ':2049 ' && break
    sleep 1
done
systemctl is-active --quiet rclone-nfs-server.service || fail "NFS-Server läuft nicht"
ok "NFS-Server aktiv"

# ------------------------------------------------------------
# SCHRITT 3: 1:1-Mount am ALTEN Pfad
# ------------------------------------------------------------
log "Schritt 3: Mounte NFS nach $MOUNT_PATH (identisch zu altem FUSE-Mount)..."
umount "$LEGACY_PATH" 2>/dev/null || true
umount "$MOUNT_PATH" 2>/dev/null || true
mkdir -p "$MOUNT_PATH"
mount -t nfs -o port=2049,mountport=2049,tcp,vers=3,hard,timeo=600,retrans=2 127.0.0.1:/ "$MOUNT_PATH"
mountpoint -q "$MOUNT_PATH" || fail "Mount fehlgeschlagen"
ok "Gemountet: $MOUNT_PATH"

# ------------------------------------------------------------
# SCHRITT 4: rclone-Dir-Cache aufwärmen
# (kritisch, sonst sieht Jellyfin beim Scan evtl. leere Ordner)
# ------------------------------------------------------------
log "Schritt 4: Wärme rclone-Verzeichnis-Cache auf (kann dauern)..."
mapfile -t TOP_DIRS < <(ls -1 "$MOUNT_PATH" 2>/dev/null || true)
if [[ ${#TOP_DIRS[@]} -eq 0 ]]; then
    fail "Mount zeigt keine Ordner – rclone-Server liefert nichts zurück"
fi
echo "   Top-Level-Einträge: ${#TOP_DIRS[@]}"

for d in "${TOP_DIRS[@]}"; do
    # Zwei Ebenen tief lesen, damit rclone Sub-Dirs cacht
    timeout 60 find "$MOUNT_PATH/$d" -maxdepth 2 -mindepth 1 >/dev/null 2>&1 || \
        warn "Timeout beim Aufwärmen: $d"
done
ok "Cache warmgelaufen"

# ------------------------------------------------------------
# SCHRITT 5: Verifikation gegen Remote
# ------------------------------------------------------------
log "Schritt 5: Verifiziere Mount-Inhalt gegen Remote..."

TMP_REMOTE=$(mktemp)
TMP_LOCAL=$(mktemp)
trap 'rm -f "$TMP_REMOTE" "$TMP_LOCAL"' EXIT

rclone lsf --dirs-only "$RCLONE_REMOTE" --config="$RCLONE_CONFIG" | sort > "$TMP_REMOTE"
ls -1 "$MOUNT_PATH" | sort > "$TMP_LOCAL"

if diff -q "$TMP_REMOTE" "$TMP_LOCAL" >/dev/null; then
    ok "Top-Level-Ordner stimmen 1:1 mit Remote überein"
else
    warn "Top-Level-Abweichung:"
    diff "$TMP_REMOTE" "$TMP_LOCAL" || true
fi

log "Dateianzahl Remote (rclone size):"
rclone size "$RCLONE_REMOTE" --config="$RCLONE_CONFIG" | tail -2

log "Sichtbare Dateien lokal (maxdepth 4, Timeout 180s):"
LOCAL_COUNT=$(timeout 180 find "$MOUNT_PATH" -maxdepth 4 -type f 2>/dev/null | wc -l || echo "timeout")
echo "   $LOCAL_COUNT Dateien"

# Rechte-Check
log "Berechtigungen Top-Level:"
ls -ldn "$MOUNT_PATH" "$MOUNT_PATH"/* 2>/dev/null | head -10

# ------------------------------------------------------------
# SCHRITT 6: Container recreated
# ------------------------------------------------------------
log "Schritt 6: Recreated Services außer cloudflared..."
docker compose up -d --force-recreate --no-deps "${SERVICES[@]}"
ok "Container recreated"

# Kurz warten und Status zeigen
sleep 3
docker compose ps

# ------------------------------------------------------------
# SCHRITT 7: Verifikation aus Jellyfin-Container
# ------------------------------------------------------------
log "Schritt 7: Prüfe Sichtbarkeit aus Jellyfin-Container..."
if docker compose exec -T jellyfin bash -lc 'ls -1 /media 2>/dev/null | head -20'; then
    ok "Jellyfin-Container sieht /media"
else
    warn "Jellyfin-Container sieht /media NICHT – .env prüfen"
fi

# ------------------------------------------------------------
# Abschluss
# ------------------------------------------------------------
cat <<EOF

===== FERTIG =====
Nächste Schritte in Jellyfin:
1. Bibliothek -> 'Bibliothek scannen' manuell auslösen
2. Pro Bibliothek: 'Echtzeitüberwachung' deaktivieren (NFS-kompatibel)
3. Metadaten-Refresh falls Einträge fehlen

Falls Ordner fehlen:
   - Log prüfen:  journalctl -u rclone-nfs-server.service -n 100 --no-pager
   - Mount prüfen: mount | grep "$MOUNT_PATH"
   - Rechte prüfen: ls -ldn "$MOUNT_PATH"/*
EOF
