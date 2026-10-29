# Jellyfin Media Stack

Einfacher Docker-Stack für Jellyfin, qBittorrent, Sonarr, Radarr, Prowlarr und Seerr.

## Schnellstart

Hauptstart:
```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/bash.sh | sudo bash
```

## Ablauf

`bash.sh` macht den kompletten Initial-Installationsablauf:

- Docker / Compose prüfen und bei Bedarf installieren
- `.env` und `compose.yaml` schreiben
- Medienordner anlegen
- Stack starten
- Zugangsdaten generieren
- qBittorrent API-Key auslesen und anzeigen
- danach nach `m` oder `a` fragen

`m` = manuelle Einrichtung in den Web-UIs
`a` = automatisches Setup über `a.sh`

## Manuell vs. automatisch

Manuell:
- Jellyfin im Browser einrichten
- qBittorrent mit Login und API-Key nutzen
- Sonarr/Radarr/Prowlarr/Seerr konfigurieren

Automatisch:
- `a.sh` versucht die Dienste über ihre APIs zu konfigurieren
- falls eine API nicht verfügbar ist, bleibt die manuelle Einrichtung in der GUI

## Zugangsdaten

- Benutzer: `admin`
- Passwort: zufällig generiert, 25 Zeichen
- qBittorrent API-Key: zufällig generiert, am Ende ausgegeben und in `/opt/jellyfin-media-stack/qbit_api_key.txt` gespeichert

## Standardpfade

- Medienordner: `/srv/media`
- Downloadordner: `/srv/media/downloads`
- Installationsordner: `/opt/jellyfin-media-stack`

## URLs

- Jellyfin: http://127.0.0.1:8096
- Sonarr: http://127.0.0.1:8989
- Radarr: http://127.0.0.1:7878
- Prowlarr: http://127.0.0.1:9696
- Seerr: http://127.0.0.1:5055
- qBittorrent: http://127.0.0.1:8080

## Wichtig

- Es gibt keinen `scr`-Ordner mehr.
- `bash.sh` ist der Haupt-Entrypoint.
- `a.sh` ist der Auto-Setup-Teil.
- qBittorrent API-Key ist separat sichtbar und kopierbar.
