# Jellyfin Media Stack

Einfaches Docker-Setup für Jellyfin, qBittorrent, Sonarr, Radarr, Prowlarr und Seerr.

## Schnellstart

Interaktiv starten:
```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/bash.sh | sudo bash
```

Automatisch starten:
```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/a.sh | sudo bash
```

## Was das Setup macht

- prüft Debian/Ubuntu und Docker/Compose
- installiert Docker automatisch, falls erforderlich
- prüft bzw. legt den Medienpfad an
- erzeugt zufällige 25-Zeichen-Passwörter
- setzt für alle relevanten Web-UIs den Benutzer `admin`
- erzeugt einen eigenen qBittorrent-API-Key
- schreibt `.env` und `compose.yaml` nach `/opt/jellyfin-media-stack`
- startet den kompletten Stack
- zeigt am Ende alle URLs, Zugangsdaten und Schlüssel an

## Zugangsdaten

- Benutzername: `admin`
- Passwort: zufällig erzeugt, 25 Zeichen
- qBittorrent API-Key: ebenfalls zufällig erzeugt, am Ende angezeigt und in `qbit_api_key.txt` gespeichert

## Standardpfade

- Medienordner: `/srv/media`
- Downloadordner: `/srv/media/downloads`
- Installationsordner: `/opt/jellyfin-media-stack`

## Infos

- qBittorrent: http://127.0.0.1:8080
- Jellyfin: http://127.0.0.1:8096
- Sonarr: http://127.0.0.1:8989
- Radarr: http://127.0.0.1:7878
- Prowlarr: http://127.0.0.1:9696
- Seerr: http://127.0.0.1:5055

Der qBittorrent-API-Key wird wie die anderen Zugangsdaten am Ende ausgegeben und zusätzlich in `/opt/jellyfin-media-stack/qbit_api_key.txt` gespeichert.
