# Homelab Docker (IaC)

Two-server homelab built entirely with Infrastructure as Code.

| Server | Role | Hostname |
|--------|------|----------|
| **Media Server** | Media, photos, music, dashboard, reverse proxy | `homelab-media` |
| **AI Server** | Local LLMs, metrics, receipt tracking | `homelab-ai` |

Everything is defined in Git. The only manual steps are cloning the repo and running the provided scripts.

---

## Architecture

```
Internet
   │
   ▼
Caddy (DuckDNS + TLS)  ←── Media Server
   │
   ├── Jellyfin
   ├── Navidrome
   ├── Immich
   ├── Homepage
   ├── PriceBuddy / PriceCheck
   └── Glances

Tailscale mesh
   │
   ├── Media Server (homelab-media)
   └── AI Server (homelab-ai)
           ├── Ollama
           ├── Open WebUI
           ├── Grafana
           ├── Receipt Tracker
           └── Glances

Nightly backup (04:00)
   Media Server ──rsync/SSH──▶ Mac external drive (5TB_Server_Backup)
```

- **Caddy** handles public HTTPS reverse proxy via DuckDNS.
- **Tailscale** provides secure private networking + SSH between the two machines and your devices.
- **Immich photos + database** are backed up nightly to a Mac external drive over SSH.
- All configuration lives in this repository. Persistent data (media libraries, Immich photos, Jellyfin config, Navidrome data, etc.) lives on the host filesystem / external drive.

---

## Services

### Media Server (`homelab-media`)

| Service | Purpose |
|---------|---------|
| **Jellyfin** | Media server (movies, TV, music) |
| **Navidrome** | Music streaming server (Subsonic API – used with Amperfy on iOS) |
| **Immich** | Self-hosted Google Photos alternative |
| **Homepage** | Dashboard |
| **Caddy + DuckDNS** | Reverse proxy + automatic TLS certificates |
| **PriceBuddy** | Price tracking |
| **PriceCheck** | Barcode price lookup |
| **Glances** | System metrics (CPU, RAM, disk, temp, uptime) |
| **Docker Socket Proxy** | Secure access to Docker socket for Homepage widgets |
| **Scrypted** | Camera / home automation (currently disabled – waiting for better hardware) |

### AI Server (`homelab-ai`)

| Service | Purpose |
|---------|---------|
| **Ollama** | Local LLM engine |
| **Open WebUI** | Web interface for Ollama |
| **Grafana** | Metrics dashboards |
| **Receipt Tracker** | Grocery spend tracking |
| **Glances** | System metrics |
| **Docker Socket Proxy** | Secure Docker socket access |

---

## Repository Structure

```
.
├── homelab-media/          # Compose file for Media Server
├── homelab-ai/             # Compose file for AI Server
├── services/               # Modular service definitions
│   ├── ai/
│   ├── dockerproxy/
│   ├── glances/
│   ├── grafana/
│   ├── homepage/
│   ├── immich/
│   ├── jellyfin/
│   ├── navidrone/          # Navidrome (music streaming)
│   ├── pricebuddy/
│   ├── pricecheck/
│   ├── public/             # Caddy + DuckDNS
│   ├── receipt-tracker/
│   └── scrypted/           # Currently disabled
├── scripts/
│   ├── setup-media.sh      # Full Media Server bootstrap (+ installs backup cron)
│   ├── setup-ai.sh         # Full AI Server bootstrap
│   ├── setup-git.sh        # Sync repo from GitHub
│   ├── auth.sh             # Create .env symlinks
│   ├── backup.sh           # Nightly Immich photo + DB backup to Mac
│   └── update-media.sh     # Pull + recreate all running stacks
├── backups/                # Local logs (and optional restore archives)
│   └── logs/
├── configtemplates/        # Optional host-level configs (Samba, SnapRAID)
├── .env                    # Secrets & variables (gitignored)
└── README.md
```

---

## Prerequisites

- Ubuntu / Debian based hosts
- External drive for media (Media Server) – script auto-detects the large exFAT volume
- A GitHub SSH key already present on the machines
- A populated `.env` file (see below)
- For Immich backups: passwordless SSH from the Media Server to the Mac, and the backup drive mounted on the Mac

---

## Initial Setup (IaC)

### 1. Prepare `.env`

On your local machine create a `.env` file (never commit it) with at least:

```env
# User
PUID=1000
PGID=1000
TZ=America/New_York

# Git
GITHUB_REPO=git@github.com:4g5fwf95j8-bit/homelab-docker.git
GIT_BRANCH=main

# Tailscale
TAILSCALE_AUTHKEY=tskey-auth-xxxxx

# DuckDNS / Caddy
DOMAIN=gsofianos.duckdns.org
DUCKDNS_TOKEN=xxxxx
DUCKDNS_SUBDOMAINLIST=jellyfin,immich,homepage,ai,grafana,pricebuddy,pricecheck,navidrome,receipts
EMAIL_ADMIN=you@example.com

# Ports (examples)
PORT_CADDY_HTTP=80
PORT_CADDY_HTTPS=443
PORT_CADDY_ADMIN=2019
PORT_NAVIDROME=4533

# Paths
MEDIADIR=/mnt/seagate_storage/jellyfin
NAVIDROME_DATA_DIR=/opt/navidrome/data

# Immich paths
DIR_PHOTOS=/mnt/seagate_storage/immich

# Immich nightly backup → Mac external drive
MAC_BACKUP_HOST=192.168.x.x          # Mac LAN IP or hostname
MAC_BACKUP_USER=georgesofianos       # Mac username
MAC_BACKUP_PATH=/Volumes/5TB_Server_Backup
MAC_BACKUP_SSH_KEY=/home/gsofianos/.ssh/id_ed25519_mac_backup   # optional, has default
MAC_BACKUP_INCLUDE_DB=true           # also dump Postgres (recommended)
MAC_BACKUP_DB_RETENTION_DAYS=14      # how many days of DB dumps to keep on the Mac
IMMICH_DB_USERNAME=postgres
```

Copy the `.env` to both servers (or use your preferred secret sync method).

### 2. One-time Mac backup SSH key (required for Immich backups)

On the Media Server generate a dedicated key (if you don’t already have one):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_mac_backup -N ""
ssh-copy-id -i ~/.ssh/id_ed25519_mac_backup.pub georgesofianos@<MAC_IP>
```

Verify passwordless access:

```bash
ssh -i ~/.ssh/id_ed25519_mac_backup georgesofianos@<MAC_IP> "ls /Volumes/5TB_Server_Backup"
```

### 3. Bootstrap Media Server

```bash
# On the Media Server
sudo mkdir -p /opt/docker
cd /opt/docker
git clone git@github.com:4g5fwf95j8-bit/homelab-docker.git
cd homelab-docker

# Place your .env in the repo root
sudo ./scripts/setup-media.sh
```

The script will:

- Sync the latest code from GitHub
- Install Docker (if missing)
- Install & authenticate Tailscale
- Detect and mount the Seagate drive
- Create required directories (including Navidrome data dir when configured)
- Restore Immich / Jellyfin backups if present
- Symlink `.env` into every service
- Pull, build and start the entire Media stack
- Install a cron job that runs the Immich backup every night at 04:00

### 4. Bootstrap AI Server

```bash
# On the AI Server
sudo mkdir -p /opt/docker
cd /opt/docker
git clone git@github.com:4g5fwf95j8-bit/homelab-docker.git
cd homelab-docker

# Place the same .env
sudo ./scripts/setup-ai.sh
```

---

## Immich Backup

The backup is fully automated by Infrastructure as Code.

| What | Details |
|------|---------|
| **Script** | `scripts/backup.sh` |
| **Schedule** | Nightly at 04:00 (installed by `setup-media.sh`) |
| **Source** | `$DIR_PHOTOS` on the Media Server |
| **Destination** | `$MAC_BACKUP_PATH/immich/` on the Mac |
| **Method** | `rsync --ignore-existing` over SSH (new files only, never overwrites) |
| **Database** | Optional Postgres dump → `$MAC_BACKUP_PATH/immich-db/` (kept for `$MAC_BACKUP_DB_RETENTION_DAYS` days) |
| **Logs** | `backups/logs/immich-backup.log` |

### Behaviour

- Safe to run repeatedly — existing files on the Mac are never touched.
- If the Mac is asleep, offline, or the drive is unplugged, the script exits cleanly and logs the failure (no hang).
- Thumbnails (`thumbs/`) are excluded to save space; they can be regenerated by Immich.

### Manual run

```bash
# On the Media Server
./scripts/backup.sh
```

### Check the cron job

```bash
crontab -l
# Should show: 0 4 * * * /opt/docker/homelab-docker/scripts/backup.sh ...
```

### Restore notes

- **Photos**: copy the desired files back from the Mac drive into `$DIR_PHOTOS`.
- **Database**: gunzip the dump and restore into the `immich_postgres` container (see Immich official docs).  
  The setup script will also automatically restore from `backups/immich-backup.tar.gz` if `/opt/immich` is empty on first boot.

---

## Day-to-day Operations

All changes should be made in Git, then deployed with the scripts.

### Sync latest code to a server

```bash
cd /opt/docker/homelab-docker
sudo ./scripts/setup-git.sh
```

### Full re-deploy (Media)

```bash
sudo ./scripts/setup-media.sh
```

### Full re-deploy (AI)

```bash
sudo ./scripts/setup-ai.sh
```

### Update running containers only

```bash
sudo ./scripts/update-media.sh
```

### View running containers

```bash
docker ps
```

### View logs

```bash
# Entire stack
cd /opt/docker/homelab-docker/homelab-media
docker compose logs -f

# Single service
docker compose logs -f jellyfin
docker compose logs -f navidrome

# Backup log
tail -f /opt/docker/homelab-docker/backups/logs/immich-backup.log
```

### Stop a stack

```bash
cd /opt/docker/homelab-docker/homelab-media
docker compose down --remove-orphans
```

---

## Adding a New Service (IaC workflow)

1. **Create the service definition**
   ```bash
   mkdir -p services/myservice
   # Add docker-compose.yml (and any staticconfig / dockerfiles)
   ```

2. **Include it in the correct stack**
   - Media → edit `homelab-media/docker-compose.yml`
   - AI → edit `homelab-ai/docker-compose.yml`

   ```yaml
   include:
     - path: ../services/myservice/docker-compose.yml
   ```

3. **Add any new variables** to `.env` (and document them).

4. **Commit & push**

5. **Deploy**
   ```bash
   # On the target server
   sudo ./scripts/setup-media.sh   # or setup-ai.sh
   ```

### Exposing a service publicly (Caddy)

Edit the Caddyfile (under `services/public/staticconfig/caddy/`) and add a block:

```caddy
myservice.{$DOMAIN} {
    reverse_proxy myservice:PORT
}
```

Then re-deploy the Media stack so Caddy picks up the change.

### Opening ports

Ports are controlled exclusively through variables in `.env` (e.g. `PORT_CADDY_HTTP`).  
Never hard-code host ports in the compose files.

---

## Homepage Configuration

Homepage configs live in:

```
services/homepage/configtemplates/homepage/
```

The setup script automatically rsyncs them to `/srv/homepage/`.

After changing Homepage YAML (services, widgets, layout, custom.css):

1. Commit the change
2. Re-run `sudo ./scripts/setup-media.sh`  
   (or manually rsync + restart the homepage container)

---

## Common Maintenance Commands

```bash
# Prune unused images
docker image prune -f

# Full system prune (careful)
docker system prune -af

# Check disk usage
docker system df

# Restart a single container
docker restart jellyfin
docker restart navidrome

# Enter a container
docker exec -it ollama bash

# Pull a new Ollama model
docker exec -it ollama ollama pull qwen2.5-coder:7b

# Manual Immich backup
./scripts/backup.sh
```

---

## Making Updates to .env File

- Make them in the VS Code version
- run this to copy it to the server:

```
syncenv
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Containers not starting | `docker compose logs -f` in the relevant stack directory |
| `.env` not found | Ensure `.env` is in the repo root and run `scripts/auth.sh` |
| Seagate drive not mounted | Re-run `setup-media.sh` – it auto-detects the large exFAT volume |
| Tailscale not connected | Check `TAILSCALE_AUTHKEY` in `.env` and re-run the setup script |
| Caddy certificate errors | Verify `DUCKDNS_TOKEN` and that the subdomain is listed in `DUCKDNS_SUBDOMAINLIST` |
| Permission errors | Confirm `PUID`/`PGID` match the host user |
| Git pull fails under sudo | The setup scripts handle SSH key selection automatically |
| Immich backup fails | Check `backups/logs/immich-backup.log`. Common causes: Mac asleep, drive unplugged, or SSH key not authorised |
| Backup cron missing | Re-run `sudo ./scripts/setup-media.sh` (it re-installs the cron job idempotently) |
| Navidrome not scanning music | Confirm `${MEDIADIR}/music` exists and is readable by `PUID`/`PGID`; check `docker compose logs -f navidrome` |

---

## Design Principles

- **Everything as Code** – no manual container configuration
- **Idempotent scripts** – safe to re-run
- **Single source of truth** – one shared `.env` (symlinked)
- **Separation of concerns** – Media and AI stacks are independent
- **Secure by default** – Tailscale for private access, Caddy for public TLS
- **Safe backups** – rsync never overwrites existing files; DB dumps are retained for a configurable period

---

## License

Private repository – for personal use.
```