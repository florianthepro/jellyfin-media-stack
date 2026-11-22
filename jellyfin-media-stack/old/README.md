# Setup Jellyfin Media Stack
`curl -fsSL 'https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/jfms.sh' | sudo bash`
### rclone if needet
```
sudo bash -c 'set -Eeuo pipefail; clear; U="${SUDO_USER:-$(logname 2>/dev/null || true)}"; test -n "$U" && test "$U" != root || { echo "FEHLER: Benutzer nicht erkannt"; exit 1; }; G="$(id -gn "$U")"; H="$(getent passwd "$U" | cut -d: -f6)"; C="$H/.config/rclone/rclone.conf"; M="/mnt/internxt"; V="/var/cache/rclone-internxt"; N="rclone-internxt.service"; F="/etc/systemd/system/$N"; D="/etc/systemd/system/$N.d"; O="$D/override.conf"; fail(){ echo; echo "FEHLER: $*" >&2; exit 1; }; step(){ echo; echo "=== $* ==="; }; version_ok(){ command -v rclone >/dev/null 2>&1 || return 1; local VSN; VSN="$(rclone version 2>/dev/null | head -1 | sed -E "s/^rclone v([0-9]+\.[0-9]+\.[0-9]+).*/\1/")"; test -n "$VSN" || return 1; dpkg --compare-versions "$VSN" ge "1.73.0"; }; healthy(){ timeout 5 systemctl is-active --quiet "$N" && timeout 5 mountpoint -q "$M" && timeout --kill-after=2 8 sudo -u "$U" -H ls -U "$M" >/dev/null 2>&1; }; step "INTERNXT SETUP"; echo "Benutzer: $U"; echo "Home:     $H"; step "1/6 VORAUSSETZUNGEN"; X=(); dpkg -s fuse3 >/dev/null 2>&1 || X+=(fuse3); command -v curl >/dev/null 2>&1 || X+=(curl); command -v unzip >/dev/null 2>&1 || X+=(unzip); if ((${#X[@]})); then echo "Installiere: ${X[*]}"; apt-get update -qq; apt-get install -y -qq "${X[@]}" >/tmp/internxt-apt.log 2>&1 || { tail -40 /tmp/internxt-apt.log; fail "Paketinstallation fehlgeschlagen"; }; else echo "Pakete: OK"; fi; test -e /dev/fuse || fail "/dev/fuse fehlt"; if version_ok; then echo "rclone: $(rclone version | head -1), Internxt-kompatibel"; else echo "rclone fehlt oder ist älter als v1.73.0, installiere aktuelle Version"; curl -fsSL https://rclone.org/install.sh -o /tmp/rclone-install.sh || fail "Installer konnte nicht geladen werden"; bash /tmp/rclone-install.sh >/tmp/rclone-install.log 2>&1 || true; rm -f /tmp/rclone-install.sh; version_ok || { tail -40 /tmp/rclone-install.log 2>/dev/null || true; fail "Keine Internxt-kompatible rclone-Version installiert"; }; echo "rclone: $(rclone version | head -1), Installation OK"; fi; touch /etc/fuse.conf; grep -qxF user_allow_other /etc/fuse.conf || { echo user_allow_other >>/etc/fuse.conf; echo "FUSE: user_allow_other ergänzt"; }; install -d -o "$U" -g "$G" -m 0700 "$(dirname "$C")"; install -d -o "$U" -g "$G" -m 0750 "$V"; step "2/6 INTERNXT-REMOTE"; if ! test -s "$C" || ! timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:"; then echo "Remote internxt: fehlt. Interaktive Einrichtung startet."; echo "Remote bitte exakt internxt nennen."; sudo -u "$U" -H rclone --config "$C" config; fi; timeout 15 sudo -u "$U" -H rclone --config "$C" listremotes 2>/dev/null | grep -Fxq "internxt:" || fail "Remote internxt: fehlt"; chown "$U:$G" "$C"; chmod 600 "$C"; echo "Remote internxt: OK"; step "3/6 SYSTEMD"; T="$(mktemp)"; Q="$(mktemp)"; trap "rm -f \"$T\" \"$Q\" /tmp/internxt-apt.log /tmp/rclone-install.log /tmp/internxt-verify.log" EXIT; printf "%s\n" "[Unit]" "Description=Internxt rclone mount for $U" "Wants=network-online.target" "After=network-online.target" "Before=docker.service" "RequiresMountsFor=/mnt" "" "[Service]" "Type=notify" "User=$U" "Group=$G" "ExecStart=/usr/bin/rclone mount internxt:media /mnt/internxt --config=$C --cache-dir=$V --vfs-cache-mode=full --vfs-cache-max-age=5m --vfs-cache-max-size=5G --dir-cache-time=1m --buffer-size=16M --allow-other --default-permissions --umask=002 --log-level=INFO" "ExecStop=/bin/fusermount3 -uz /mnt/internxt" "Restart=on-failure" "RestartSec=10" "TimeoutStartSec=90" "TimeoutStopSec=30" "KillMode=mixed" "" "[Install]" "WantedBy=multi-user.target" >"$T"; printf "%s\n" "[Service]" "MemoryLow=128M" "MemoryHigh=512M" "MemoryMax=768M" "MemorySwapMax=256M" "CPUWeight=100" >"$Q"; Z=0; if test -f "$F" && cmp -s "$T" "$F"; then echo "Dienstdatei: korrekt"; else install -o root -g root -m 0644 "$T" "$F"; Z=1; echo "Dienstdatei: korrigiert"; fi; install -d -m 0755 "$D"; if test -f "$O" && cmp -s "$Q" "$O"; then echo "Ressourcenlimits: korrekt"; else install -o root -g root -m 0644 "$Q" "$O"; Z=1; echo "Ressourcenlimits: korrigiert"; fi; timeout 15 systemctl daemon-reload || fail "daemon-reload fehlgeschlagen"; timeout 15 systemd-analyze verify "$F" >/tmp/internxt-verify.log 2>&1 || { cat /tmp/internxt-verify.log; fail "Systemd-Konfiguration ungültig"; }; timeout 15 systemctl enable "$N" >/dev/null 2>&1 || fail "Dienst konnte nicht aktiviert werden"; systemctl reset-failed "$N" 2>/dev/null || true; step "4/6 MOUNT PRÜFEN"; if healthy; then echo "Mount: gesund, kein Neustart"; test "$Z" -eq 0 || echo "Neue Dienstkonfiguration gilt beim nächsten Remount."; else step "5/6 MOUNT REPARIEREN"; timeout --kill-after=10 120 systemctl stop "$N" >/dev/null 2>&1 || true; mapfile -t P < <(pgrep -f "^/usr/bin/rclone mount internxt:media /mnt/internxt([[:space:]]|$)" || true); if ((${#P[@]})); then kill -TERM "${P[@]}" 2>/dev/null || true; sleep 5; for I in "${P[@]}"; do kill -0 "$I" 2>/dev/null && kill -KILL "$I" 2>/dev/null || true; done; fi; timeout 20 fusermount3 -uz "$M" 2>/dev/null || timeout 20 umount -fl "$M" 2>/dev/null || true; sleep 3; findmnt --mountpoint "$M" >/dev/null 2>&1 && { timeout 20 umount -fl "$M" 2>/dev/null || true; sleep 3; }; findmnt --mountpoint "$M" >/dev/null 2>&1 && fail "Alter FUSE-Mount weiterhin registriert"; rm -rf "$M"; install -d -o "$U" -g "$G" -m 0775 "$M"; install -d -o "$U" -g "$G" -m 0750 "$V"; echo "Starte Dienst"; systemctl start "$N" >/dev/null 2>&1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienststart fehlgeschlagen"; }; K=0; for I in $(seq 1 60); do if healthy; then K=1; break; fi; if systemctl is-failed --quiet "$N"; then journalctl -u "$N" -n 40 --no-pager -o cat; fail "Dienst fehlgeschlagen"; fi; printf "\rWarte: %3d/120 Sekunden" "$((I*2))"; sleep 2; done; echo; test "$K" -eq 1 || { journalctl -u "$N" -n 40 --no-pager -o cat; fail "Mount nicht erreichbar"; }; echo "Mount: repariert"; fi; step "6/6 ERGEBNIS"; healthy || fail "Abschlussprüfung fehlgeschlagen"; echo "Status:   ERFOLG"; echo "rclone:   $(rclone version | head -1)"; echo "Benutzer: $U"; findmnt --mountpoint "$M" -o TARGET,SOURCE,FSTYPE,OPTIONS; echo; timeout 10 sudo -u "$U" -H ls -Ula "$M" | head -20; echo; echo "Docker und andere Projekte wurden nicht neu gestartet."'
```
---

## install
```
rm -f ~/setup-jfms.sh && sudo nano ~/setup-jfms.sh && sudo chmod +x ~/setup-jfms.sh && sudo ~/setup-jfms.sh && sudo rm ~/setup-jfms.sh
```
[input](setup-jfms.sh)

---
## [backup:](/backup)

```
sudo bash -c 'set -euo pipefail; F=/usr/local/sbin/jfms-config-backup; do_backup(){ exec 9>/run/lock/jfms-config-backup.lock; flock -w 2 9||{ echo "Backup läuft bereits."; return 1; }; src=/opt/jfms; bdir=/opt/jfms/backup; [[ -d "$src/config" ]]||{ echo "Fehlt: $src/config">&2; return 1; }; [[ -f "$src/compose.yaml" ]]||{ echo "Fehlt: $src/compose.yaml">&2; return 1; }; mkdir -p "$bdir"; umask 077; d=$(date +%Y%m%d); n=1; f="$bdir/jfms-config-$d-v$n.tar"; while [[ -e "$f" ]]; do n=$((n+1)); f="$bdir/jfms-config-$d-v$n.tar"; done; tmp=$(mktemp "$bdir/.jfms-config-$d-v$n.XXXXXX"); trap "rm -f -- $tmp 2>/dev/null||true" EXIT; tar --numeric-owner --acls --xattrs -cpf "$tmp" -C "$src" config compose.yaml; tar -tf "$tmp" >/dev/null; mv -- "$tmp" "$f"; trap - EXIT; matching=(); for file in "$bdir"/jfms-config-*.tar; do [[ -f "$file" ]]||continue; base=${file##*/}; [[ "$base" =~ ^jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar$ ]]&&matching+=("$file"); done; if ((${#matching[@]}>3)); then mapfile -t sorted < <(printf "%s\n" "${matching[@]}"|sort -V); rm_count=$((${#sorted[@]}-3)); for ((i=0;i<rm_count;i++)); do rm -f -- "${sorted[i]}"; done; fi; echo "Backup: $f"; sha256sum "$f" 2>/dev/null||true; sip=$(awk "{print \$1}" <<< "${SSH_CONNECTION:-}" 2>/dev/null||true); [[ -n "$sip" ]]&&printf "scp \"%s@%s:%s\" /ziel/\n" "${USER:-root}" "$sip" "$f"; exec 9>&-; }; do_restore(){ root=/opt/jfms; exec 9>/run/lock/jfms-config-restore.lock; flock -n 9||{ echo "Wiederherstellung läuft bereits."; return 1; }; read -rp "Archiv: 1) /tmp 2) $root/backup [2]: " w; case "${w:-2}" in 1) d=/tmp;; 2) d="$root/backup";; *) echo "Ungültig"; return 1;; esac; [[ -d "$d" ]]||{ echo "Fehlt: $d"; return 1; }; mapfile -t a < <(find "$d" -maxdepth 1 -type f -regextype posix-extended -regex ".*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar" -printf "%f\n"|sort -V); ((${#a[@]}))||{ echo "Keine Archive."; return 1; }; printf "%s\n" "${a[@]}"|nl -v1; read -rp "Nr [${#a[@]}]: " n || return 1; n=${n:-${#a[@]}}; [[ "$n" =~ ^[0-9]+$ ]]||return 1; ix=$((10#$n-1)); ((ix>=0&&ix<${#a[@]}))||return 1; f="$d/${a[ix]}"; t=$(mktemp -d "$root/.jfms-restore.XXXXXX"); committed=0; targets=(); backups=(); had=(); installed=(); cleanup_restore(){ local rc=$?; trap - EXIT; if ((rc!=0&&committed==0)); then set +e; for ((i=${#targets[@]}-1;i>=0;i--)); do ((installed[i]))&&rm -rf -- "${targets[i]}"; ((had[i]))&&mv -- "${backups[i]}" "${targets[i]}"; done; fi; [[ -z "${t:-}" ]]||rm -rf -- "$t"; exit "$rc"; }; trap cleanup_restore EXIT; tar -tf "$f" > "$t/members"||return 1; hc=0; hp=0; while IFS= read -r m; do [[ "$m" != /* && ! "$m" =~ (^|/)\.\.(/|$) ]]||{ echo "Unsicher: $m"; return 1; }; case "$m" in config|config/|config/*) hc=1;; compose.yaml) hp=1;; *) echo "Unerwartet: $m"; return 1;; esac; done < "$t/members"; ((hc&&hp))||return 1; mkdir "$t/new"; tar --numeric-owner --acls --xattrs -xpf "$f" -C "$t/new" config compose.yaml; [[ -d "$t/new/config" && -f "$t/new/compose.yaml" ]]||return 1; read -rp "1) config/ ersetzen 2) Unterordner [1]: " scope; all=0; dirs=(); case "${scope:-1}" in 1) all=1;; 2) [[ -d "$root/config" ]]||return 1; mapfile -t available < <(find "$t/new/config" -mindepth 1 -maxdepth 1 -type d -printf "%f\n"|sort -V); ((${#available[@]}))||return 1; printf "%s\n" "${available[@]}"|nl -v1; read -rp "Nummern: " picks || return 1; IFS="," read -r -a ps <<< "$picks"; for p in "${ps[@]}"; do p=${p//[[:space:]]/}; [[ "$p" =~ ^[0-9]+$ ]]||return 1; j=$((10#$p-1)); ((j>=0&&j<${#available[@]}))||return 1; x=${available[j]}; dup=0; for y in "${dirs[@]}"; do [[ "$y" == "$x" ]]&&dup=1; done; ((dup))||dirs+=("$x"); done; ((${#dirs[@]}))||return 1;; *) return 1;; esac; read -rp "compose.yaml auch? [J/n]: " cpchoice; rc_c=1; case "${cpchoice,,}" in n|nein) rc_c=0;; esac; replace(){ s=$1; dd=$2; i=${#targets[@]}; b="$t/old/$i"; mkdir -p "$t/old"; targets+=("$dd"); backups+=("$b"); had+=(0); installed+=(0); if [[ -e "$dd" || -L "$dd" ]]; then mv -- "$dd" "$b"; had[i]=1; fi; mv -- "$s" "$dd"; installed[i]=1; }; if ((all)); then replace "$t/new/config" "$root/config"; else for x in "${dirs[@]}"; do replace "$t/new/config/$x" "$root/config/$x"; done; fi; ((rc_c))&&replace "$t/new/compose.yaml" "$root/compose.yaml"; committed=1; rm -rf -- "$t"; t=; trap - EXIT; echo "Wiederhergestellt."; read -rp "1) alle 2) auswählen 3) keine [3]: " action; action=${action:-3}; case "$action" in 3) return 0;; 1|2) ;; *) return 1;; esac; dc=(docker compose --project-directory "$root" -f "$root/compose.yaml"); services_text=$("${dc[@]}" config --services)||return 1; [[ -n "$services_text" ]]||return 1; mapfile -t services <<< "$services_text"; if [[ "$action" == 1 ]]; then "${dc[@]}" up -d; else printf "%s\n" "${services[@]}"|nl -v1; read -rp "Nummern: " picks || return 1; IFS="," read -r -a ps <<< "$picks"; chosen=(); for p in "${ps[@]}"; do p=${p//[[:space:]]/}; [[ "$p" =~ ^[0-9]+$ ]]||return 1; j=$((10#$p-1)); ((j>=0&&j<${#services[@]}))||return 1; chosen+=("${services[j]}"); done; ((${#chosen[@]}))||return 1; "${dc[@]}" up -d "${chosen[@]}"; fi; }; do_show(){ f=$(find /opt/jfms/backup -maxdepth 1 -type f -regextype posix-extended -regex ".*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar" -printf "%f\n" 2>/dev/null|sort -V|tail -n1); [[ -n "$f" ]]||{ echo "Kein Backup vorhanden."; return 1; }; echo "Inhalt: $f (Tiefe 1-4)"; tar -tf "/opt/jfms/backup/$f"|awk -F/ "NF <= 4"; }; install_svc(){ { echo "#!/usr/bin/env bash"; echo "set -euo pipefail"; echo "F=$F"; declare -f do_backup do_restore do_show install_svc uninstall_svc main; echo "main \"\$@\""; } > "$F"; chmod 755 "$F"; printf "%s\n" "[Unit]" "Description=JFMS Backup" "" "[Service]" "Type=oneshot" "ExecStart=$F --backup-only" > /etc/systemd/system/jfms-config-backup.service; printf "%s\n" "[Unit]" "Description=JFMS Backup Timer" "" "[Timer]" "OnCalendar=*-*-* 02:00:00" "Persistent=true" "Unit=jfms-config-backup.service" "" "[Install]" "WantedBy=timers.target" > /etc/systemd/system/jfms-config-backup.timer; systemctl daemon-reload; systemctl enable --now jfms-config-backup.timer; echo "Service installiert: $F"; }; uninstall_svc(){ systemctl disable --now jfms-config-backup.timer 2>/dev/null||true; rm -f /etc/systemd/system/jfms-config-backup.service /etc/systemd/system/jfms-config-backup.timer "$F"; systemctl daemon-reload; echo "Entfernt."; }; main(){ [[ "${1:-}" == "--backup-only" ]]&&{ do_backup; return; }; [[ $EUID -eq 0 ]]||{ echo "Root nötig">&2; return 1; }; while true; do echo; echo "=== JFMS Backup-Verwaltung ==="; echo "1) Backup jetzt erstellen"; echo "2) Backup wiederherstellen"; echo "3) Neuestes Backup anzeigen"; if [[ -f "$F" ]]; then echo "4) Backup-Service deinstallieren"; else echo "4) Backup-Service installieren (täglich 02:00)"; fi; echo "5) Beenden"; read -rp "Auswahl [5]: " c || exit 0; case "${c:-5}" in 1) ( do_backup )||true;; 2) ( do_restore )||true;; 3) ( do_show )||true;; 4) if [[ -f "$F" ]]; then ( uninstall_svc )||true; else ( install_svc )||true; fi;; 5) exit 0;; *) echo "Ungültig";; esac; done; }; main "$@"'
```
mehrzeilig:
```
sudo bash <<'JFMS'
set -euo pipefail

do_backup() {
    local src=/opt/jfms bdir=/opt/jfms/backup
    [[ -d "$src/config" ]]       || { echo "Fehlt: $src/config" >&2; return 1; }
    [[ -f "$src/compose.yaml" ]] || { echo "Fehlt: $src/compose.yaml" >&2; return 1; }
    mkdir -p "$bdir"
    local old_umask; old_umask=$(umask); umask 077
    local d n=1 f; d=$(date +%Y%m%d); f="$bdir/jfms-config-$d-v$n.tar"
    while [[ -e "$f" ]]; do n=$((n+1)); f="$bdir/jfms-config-$d-v$n.tar"; done
    local tmp; tmp=$(mktemp "$bdir/.jfms-config-$d-v$n.XXXXXX")
    trap 'rm -f -- "$tmp" 2>/dev/null || true' EXIT
    tar --numeric-owner --acls --xattrs -cpf "$tmp" -C "$src" config compose.yaml
    tar -tf "$tmp" >/dev/null
    mv -- "$tmp" "$f"; trap - EXIT; umask "$old_umask"
    local -a matching=() ; local file base
    for file in "$bdir"/jfms-config-*.tar; do
        [[ -f "$file" ]] || continue
        base=${file##*/}
        [[ "$base" =~ ^jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar$ ]] && matching+=("$file")
    done
    if ((${#matching[@]} > 3)); then
        local -a sorted
        mapfile -t sorted < <(printf '%s\n' "${matching[@]}" | sort -V)
        local rc=$((${#sorted[@]} - 3)) i
        for ((i=0;i<rc;i++)); do rm -f -- "${sorted[i]}"; done
    fi
    echo "Backup erstellt und geprüft: $f"
    sha256sum "$f" 2>/dev/null || true
    local sip; sip=$(awk '{print $1}' <<< "${SSH_CONNECTION:-}" 2>/dev/null || true)
    [[ -n "$sip" ]] && printf 'Auf Zielmaschine ausführen:\nscp "%s@%s:%s" /ziel/\n' "${USER:-root}" "$sip" "$f"
}

do_restore() {
    local root=/opt/jfms
    exec 9>/run/lock/jfms-config-restore.lock
    flock -n 9 || { echo "Wiederherstellung läuft bereits."; return 1; }
    local w; read -r -p "Archivverzeichnis: 1) /tmp  2) $root/backup [2]: " w
    local d; case "${w:-2}" in 1) d=/tmp;; 2) d="$root/backup";; *) echo "Ungültig."; return 1;; esac
    [[ -d "$d" ]] || { echo "Ordner fehlt: $d"; return 1; }
    local -a a
    mapfile -t a < <(find "$d" -maxdepth 1 -type f -regextype posix-extended \
        -regex '.*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar' -printf '%f\n' | sort -V)
    ((${#a[@]})) || { echo "Keine Archive."; return 1; }
    printf '%s\n' "${a[@]}" | nl -v1
    local n; read -r -p "Nummer [${#a[@]} = neuestes]: " n; n=${n:-${#a[@]}}
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "Ungültig."; return 1; }
    local ix=$((10#$n-1)); ((ix>=0 && ix<${#a[@]})) || { echo "Ungültig."; return 1; }
    local f="$d/${a[ix]}" t; t=$(mktemp -d "$root/.jfms-restore.XXXXXX")
    local committed=0
    local -a targets=() backups=() had=() installed=()
    cleanup_restore() {
        local rc=$?; trap - EXIT
        if ((rc!=0 && committed==0)); then
            set +e; local i
            for ((i=${#targets[@]}-1;i>=0;i--)); do
                ((installed[i])) && rm -rf -- "${targets[i]}"
                ((had[i]))       && mv -- "${backups[i]}" "${targets[i]}"
            done
        fi
        [[ -z "${t:-}" ]] || rm -rf -- "$t"
        exit "$rc"
    }
    trap cleanup_restore EXIT
    tar -tf "$f" > "$t/members" || { echo "Archiv nicht lesbar."; return 1; }
    local hc=0 hp=0 m
    while IFS= read -r m; do
        [[ "$m" != /* && ! "$m" =~ (^|/)\.\.(/|$) ]] || { echo "Unsicher: $m"; return 1; }
        case "$m" in config|config/|config/*) hc=1;; compose.yaml) hp=1;; *) echo "Unerwartet: $m"; return 1;; esac
    done < "$t/members"
    ((hc && hp)) || { echo "Archiv unvollständig."; return 1; }
    mkdir "$t/new"
    tar --numeric-owner --acls --xattrs -xpf "$f" -C "$t/new" config compose.yaml
    [[ -d "$t/new/config" && -f "$t/new/compose.yaml" ]] || { echo "Archiv unvollständig."; return 1; }
    local scope; read -r -p "1) ganzes config/ ersetzen  2) Unterordner [1]: " scope
    local all=0 dirs=()
    case "${scope:-1}" in
        1) all=1;;
        2) all=0; [[ -d "$root/config" ]] || { echo "$root/config fehlt."; return 1; }
           local -a available
           mapfile -t available < <(find "$t/new/config" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
           ((${#available[@]})) || { echo "Keine Unterordner."; return 1; }
           printf '%s\n' "${available[@]}" | nl -v1
           local picks; read -r -p "Nummern (Komma): " picks
           local -a ps; IFS=',' read -r -a ps <<< "$picks"
           local p j x y dup
           for p in "${ps[@]}"; do
               p=${p//[[:space:]]/}; [[ "$p" =~ ^[0-9]+$ ]] || { echo "Ungültig: $p"; return 1; }
               j=$((10#$p-1)); ((j>=0 && j<${#available[@]})) || { echo "Ungültig: $p"; return 1; }
               x=${available[j]}; dup=0; for y in "${dirs[@]}"; do [[ "$y" == "$x" ]] && dup=1; done
               ((dup)) || dirs+=("$x")
           done
           ((${#dirs[@]})) || { echo "Keine Auswahl."; return 1; };;
        *) echo "Ungültig."; return 1;;
    esac
    local cpchoice restore_compose=1
    read -r -p "Auch compose.yaml wiederherstellen? [J/n]: " cpchoice
    case "${cpchoice,,}" in n|nein) restore_compose=0;; esac
    replace() {
        local src=$1 dst=$2 i=${#targets[@]} b="$t/old/$i"
        mkdir -p "$t/old"; targets+=("$dst"); backups+=("$b"); had+=(0); installed+=(0)
        if [[ -e "$dst" || -L "$dst" ]]; then mv -- "$dst" "$b"; had[i]=1; fi
        mv -- "$src" "$dst"; installed[i]=1
    }
    local x
    if ((all)); then replace "$t/new/config" "$root/config"
    else for x in "${dirs[@]}"; do replace "$t/new/config/$x" "$root/config/$x"; done; fi
    ((restore_compose)) && replace "$t/new/compose.yaml" "$root/compose.yaml"
    committed=1; rm -rf -- "$t"; t=
    echo "Dateien aus ${a[ix]} wiederhergestellt."
    local action; read -r -p "Services: 1) alle starten  2) auswählen  3) keine [3]: " action; action=${action:-3}
    case "$action" in 3) echo "Keine Services gestartet."; return 0;; 1|2) ;; *) echo "Ungültig; Dateien wiederhergestellt."; return 1;; esac
    local -a dc=(docker compose --project-directory "$root" -f "$root/compose.yaml")
    local services_text; services_text=$("${dc[@]}" config --services) || { echo "Compose nicht lesbar."; return 1; }
    [[ -n "$services_text" ]] || { echo "Keine Services."; return 1; }
    local -a services; mapfile -t services <<< "$services_text"
    if [[ "$action" == 1 ]]; then "${dc[@]}" up -d
    else
        printf '%s\n' "${services[@]}" | nl -v1
        local picks; read -r -p "Nummern (Komma): " picks
        local -a ps; IFS=',' read -r -a ps <<< "$picks"
        local chosen=() p j
        for p in "${ps[@]}"; do
            p=${p//[[:space:]]/}; [[ "$p" =~ ^[0-9]+$ ]] || { echo "Ungültig: $p"; return 1; }
            j=$((10#$p-1)); ((j>=0 && j<${#services[@]})) || { echo "Ungültig: $p"; return 1; }
            chosen+=("${services[j]}")
        done
        ((${#chosen[@]})) || { echo "Keine Auswahl."; return 1; }
        "${dc[@]}" up -d "${chosen[@]}"
    fi
}

do_show() {
    local f
    f=$(find /opt/jfms/backup -maxdepth 1 -type f -regextype posix-extended \
        -regex '.*/jfms-config-[0-9]{8}-v[1-9][0-9]*\.tar' -printf '%f\n' 2>/dev/null | sort -V | tail -n1)
    [[ -n "$f" ]] || { echo "Kein Backup vorhanden."; return 1; }
    echo "Inhalt von /opt/jfms/backup/$f (Tiefe 1-4):"
    tar -tf "/opt/jfms/backup/$f" | awk -F/ 'NF <= 4'
}

is_installed() {
    [[ -f /usr/local/sbin/jfms-backup && -f /etc/systemd/system/jfms-config-backup.timer ]]
}

do_install_service() {
    {
        echo '#!/usr/bin/env bash'
        echo 'set -euo pipefail'
        declare -f do_backup do_restore do_show is_installed do_install_service do_uninstall_service main
        echo 'main "$@"'
    } > /usr/local/sbin/jfms-backup
    chmod 0755 /usr/local/sbin/jfms-backup
    cat > /etc/systemd/system/jfms-config-backup.service <<'UNIT'
[Unit]
Description=Backup von JFMS-Konfiguration und Compose-Datei
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/jfms-backup --backup-only
UNIT
    cat > /etc/systemd/system/jfms-config-backup.timer <<'UNIT'
[Unit]
Description=Tägliches JFMS-Konfigurationsbackup
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
Unit=jfms-config-backup.service
[Install]
WantedBy=timers.target
UNIT
    systemctl daemon-reload
    systemctl enable --now jfms-config-backup.timer
    echo "Service installiert. Manuell aufrufen mit: sudo jfms-backup"
}

do_uninstall_service() {
    systemctl disable --now jfms-config-backup.timer 2>/dev/null || true
    rm -f /etc/systemd/system/jfms-config-backup.service /etc/systemd/system/jfms-config-backup.timer
    rm -f /usr/local/sbin/jfms-backup
    systemctl daemon-reload
    echo "Service und Kommando entfernt."
}

main() {
    if [[ "${1:-}" == "--backup-only" ]]; then do_backup; return; fi
    [[ $EUID -eq 0 ]] || { echo "Bitte mit sudo/root ausführen." >&2; return 1; }
    while true; do
        echo
        echo "=== JFMS Backup-Verwaltung ==="
        echo "1) Backup jetzt erstellen"
        echo "2) Backup wiederherstellen"
        echo "3) Neuestes Backup anzeigen"
        if is_installed; then
            echo "4) Backup-Service deinstallieren"
        else
            echo "4) Backup-Service installieren (täglich 02:00)"
        fi
        echo "5) Beenden"
        local choice; read -r -p "Auswahl [5]: " choice
        case "${choice:-5}" in
            1) ( do_backup  ) || true;;
            2) ( do_restore ) || true;;
            3) ( do_show    ) || true;;
            4) ( if is_installed; then do_uninstall_service; else do_install_service; fi ) || true;;
            5) exit 0;;
            *) echo "Ungültige Auswahl.";;
        esac
    done
}

main "$@"
JFMS
```
