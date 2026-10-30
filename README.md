`@import url("https://cdn.jsdelivr.net/gh/florianthepro/simple.css@main/simple.css");`

# Jellyfin Media Stack

Einfacher Docker-Stack für Jellyfin, qBittorrent, Sonarr, Radarr, Prowlarr und Seerr.

## Schnellstart

```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/bash.sh | sudo bash
```

## Ablauf

`bash.sh` ist der Haupt-Installer. Er macht den kompletten Initialsetup:

- Docker/Compose prüfen und bei Bedarf installieren
- `/opt/jellyfin-media-stack` anlegen
- Medienordner einrichten
- `.env` und `compose.yaml` schreiben
- Stack starten
- zufällige Zugangsdaten generieren
- qBittorrent API-Key auslesen und anzeigen
- danach nach `m` oder `a` fragen

`m` = manuelle Einrichtung in den Web-Interfaces
`a` = automatisches Setup via `a.sh`

## Manuell vs. automatisch

Manuell:
- Jellyfin im Browser konfigurieren
- qBittorrent mit admin/Login einrichten
- Sonarr / Radarr / Prowlarr / Seerr konfigurieren

Automatisch:
- `a.sh` versucht, die Apps per API bzw. über die vorhandenen Endpunkte zu konfigurieren
- falls etwas nicht erreichbar ist, bleibt die GUI-Konfiguration bestehen

## Zugangsdaten

Es werden für die wichtigsten Apps zufällige 25-Zeichen-Passwörter erzeugt.

- Benutzername: `admin`
- Passwort: zufällig erzeugt, 25 Zeichen
- qBittorrent API-Key: zufällig erzeugt, am Ende ausgegeben und zusätzlich in `/opt/jellyfin-media-stack/qbit_api_key.txt` gespeichert

## Standardpfade

- Medienpfad: `/srv/media`
- Downloadpfad: `/srv/media/downloads`
- Installationspfad: `/opt/jellyfin-media-stack`

## URLs

- Jellyfin: http://127.0.0.1:8096
- Sonarr: http://127.0.0.1:8989
- Radarr: http://127.0.0.1:7878
- Prowlarr: http://127.0.0.1:9696
- Seerr: http://127.0.0.1:5055
- qBittorrent: http://127.0.0.1:8080

## Mullvad / VPN

Das Compose-File enthält ein optionales `vpn`-Profil für Mullvad. Wenn du qBittorrent über Mullvad laufen lassen willst:

```bash
cd /opt/jellyfin-media-stack
docker compose --profile vpn up -d
```

## Hinweise

- Der `scr/`-Ordner ist nicht Teil dieses Final-Layouts.
- `bash.sh` ist der Haupt-Entrypoint.
- `a.sh` ist der Auto-Setup-Teil.
- qBittorrent API-Key ist immer separat sichtbar und kopierbar.
