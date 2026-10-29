# Jellyfin Media Stack

This repository contains a small, opinionated Docker stack for media automation and a single bootstrap entrypoint that is easier to maintain than the older `v2-setup.sh` script.

## Included

- Jellyfin
- qBittorrent
- Sonarr
- Radarr
- Prowlarr
- Seerr
- Optional Tailscale and optional Mullvad VPN profile for qBittorrent egress

## Quick start

Run the installer as root:

```bash
sudo bash ./bash.sh
```

The script defaults to `w` mode, which asks for mode selection before running. Available modes:

- `m` = manual setup
- `a` = automatic setup
- `w` = interactive wizard

## What the installer does

- checks OS and Docker prerequisites
- installs Docker if missing
- detects or asks for the media directory
- generates a random 25-character admin password
- writes `.env` and the Docker Compose definition
- starts the stack
- configures qBittorrent credentials and stores the generated API key
- prints a final summary with all service URLs and credentials

## Default credentials

The generated credentials are:

- Username: `admin`
- Password: random 25-character string (printed at the end)

For qBittorrent, a matching API key is also generated and stored in the project `.env` file.

## Mullvad support

The Compose file includes an optional `vpn` profile for a Mullvad-based egress setup. Use it only if you want qBittorrent traffic to exit through a VPN tunnel.

Example:

```bash
cd /opt/jellyfin-media-stack
sudo docker compose --profile vpn up -d
```

## qBittorrent download folder

The default downloads folder is:

```text
${MEDIA}/downloads
```

This is mounted into qBittorrent as `/downloads`, which is the default behavior for the linuxserver/qbittorrent image. If you want a different path, change `MEDIA` in `.env` before launching the stack.

## Notes about manual downloads

The qBittorrent web UI can be used manually. If you want to download data from the browser but have it land on the client device instead of the server, the recommended approach is to use a remote client (e.g. a desktop client) and point it at the qBittorrent host. The `downloads` directory inside this stack is meant for the server-based torrent workflow; client-side downloads are outside the scope of this Docker stack.

## Output summary

At the end of the bootstrap, the script prints a simple status table with:

- service URLs
- user names
- generated random password
- API key
- log paths
- next steps

## Repository layout

```text
.
├── README.md
├── compose.yaml
├── bash.sh
├── .env.example
├── scr/
│   ├── 00-common.sh
│   ├── 10-docker.sh
│   ├── 20-stack.sh
│   ├── 30-security.sh
│   └── 40-output.sh
└── LICENSE
```
