Muss gemacht werden

1. Repo-Struktur
- Das Repo soll nur diese 4 Dateien enthalten:
  - a.sh
  - bash.sh
  - README.md
  - compose.yaml

2. Neuer Einstieg
- `bash.sh` ist das neue Setup-Script.
- Es ersetzt das alte [`v2-setup.sh`](https://github.com/florianthepro/jellyfin-media-stack-old/blob/main/installation/bash/v2-setup.sh).
- Es soll zuerst prüfen, ob bereits etwas installiert ist.
- Wenn nichts da ist: Setup starten.
- Wenn etwas da ist: vorhandenen Zustand erkennen und entsprechend handeln. (man kann löschen zurücksetzten daten mengen für median usw sehen usw immer sauber nutzer entscheidet in cleaner terminalanmsicht)
- Das Script muss übersichtlich und sauber aufgebaut sein.

3. `bash.sh` Funktion
- `bash.sh` soll die Auswahl/Interaktion übernehmen.
- Es soll die Installation starten, reparieren oder verwalten.
- Es muss eine Mullvad-Option für qBittorrent enthalten (zusätzlich in compose).
- `bash.sh` ist der manuelle/interactive Einstieg.

4. `a.sh` Funktion
- `a.sh` soll den automatischen Setup-Pfad übernehmen.
- Es soll den bisherigen Final-Teil aus dem alten Script automatisieren.
- Es erzeugt:
  - Admin-Benutzer
  - 25-Zeichen-Zufallspasswort
  - passende Credentials für die wichtigsten Services
- Es setzt die Credentials automatisch und sauber.

5. qBittorrent
- qBittorrent muss mit Admin-Login und zufälligem 25-Zeichen-Passwort konfiguriert werden.
- Ein API-Key muss erzeugt und genutzt werden.
- Der Standard-Pfad für Downloads muss `/srv/media/downloads` sein.
- Der WebUI-Port muss 8080 sein.

6. Compose-Stack
- `compose.yaml` muss den kompletten Stack definieren:
  - Jellyfin
  - Seerr
  - Sonarr
  - Radarr
  - Prowlarr
  - qBittorrent
- Optional muss auch die Mullvad/VPN-Variante berücksichtigt werden.

7. README
- `README.md` muss kurz erklären:
  - wie man startet
  - was das Repo enthält
  - wie der Setup-Flow funktioniert

8. Endausgabe
- Das Setup muss am Ende eine klare Ausgabe liefern mit:
  - URLs
  - Benutzer
  - Passwort
  - qBittorrent API-Key
  - wichtige Pfade
- Die Ausgabe muss alles Wichtige für den Admin auf einen Blick sichtbar machen.

9. Abschluss
- Das alte `v2-setup.sh` wird durch die neue, minimale Struktur ersetzt.
- Das Produkt besteht aus:
  - `a.sh`
  - `bash.sh`
  - `README.md`
  - `compose.yaml`

rclone compatiblität
