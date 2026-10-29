# Jellyfin Media Stack

Einfacher Docker-Stack für Jellyfin, qBittorrent, Sonarr, Radarr, Prowlarr und Seerr.

## Schnellstart

Interaktiv / Auswahl nach Start:
```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/bash.sh | sudo bash
```

Automatisch ohne Auswahl:
```bash
curl -fsSL https://raw.githubusercontent.com/florianthepro/jellyfin-media-stack/main/a.sh | sudo bash
```

## Ablauf

- `bash.sh` ist der Haupt-Installer
- Nach dem Start aller Container fragt `bash.sh` nach `m` oder `a`
- `m` = manuelle Einrichtung in den Web-UIs
- `a` = automatisches Setup über `a.sh`
- `a.sh` ist für die automatische App-Konfiguration gedacht, nicht für die Erstinstallation von Docker oder das Starten des Stacks

## Was passieren soll

- Docker/Compose prüfen und falls nötig installieren
- Medienordner erstellen
- `.env` und `compose.yaml` schreiben
- Stack starten
- qBittorrent API-Key aus der laufenden Config auslesen
- finale Zugangsdaten ausgeben
- danach Auswahl zwischen manuellem GUI-Setup oder automatischem Setup

## Standardwerte

- Benutzer: `admin`
- Passwort: zufällig erzeugt, 25 Zeichen
- qBittorrent API-Key: zufällig erzeugt, zusätzlich in `qbit_api_key.txt` gespeichert
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

## Manuell vs automatisch

- `m` = der Nutzer richtet die Apps im Browser selbst ein
- `a` = `a.sh` versucht, die Apps automatisch per API zu konfigurieren

Die I/O-Ausgabe zeigt am Ende die echten Zugangsdaten und den qBittorrent API-Key an, damit man sie direkt kopieren kann.
