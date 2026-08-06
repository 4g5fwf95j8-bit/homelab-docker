# Homelab Docker (IaC)

Two-server homelab built entirely with Infrastructure as Code.

| Server | Role | Hostname |
|--------|------|----------|
| **Media Server** | Media, photos, dashboard, reverse proxy | `homelab-media` |
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
```

- **Caddy** handles public HTTPS reverse proxy via DuckDNS.
- **Tailscale** provides secure private networking + SSH between the two machines and your devices.
- All configuration lives in this repository. Persistent data (media libraries, Immich photos, Jellyfin config, etc.) lives on the host filesystem / external drive.

---

## Services

### Media Server (`homelab-media`)

| Service | Purpose |
|---------|---------|
| **Jellyfin** | Media server (movies, TV, music) |
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
│   ├── pricebuddy/
│   ├── pricecheck/
│   ├── public/             # Caddy + DuckDNS
│   ├── receipt-tracker/
│   └── scrypted/           # Currently disabled
├── scripts/
│   ├── setup-media.sh      # Full Media Server bootstrap
│   ├── setup-ai.sh         # Full AI Server bootstrap
│   ├── setup-git.sh        # Sync repo from GitHub
│   ├── auth.sh             # Create .env symlinks
│   └── update-media.sh     # Pull + recreate all running stacks
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
DUCKDNS_SUBDOMAINLIST=jellyfin,immich,homepage,ai,grafana
EMAIL_ADMIN=you@example.com

# Ports (examples)
PORT_CADDY_HTTP=80
PORT_CADDY_HTTPS=443
PORT_CADDY_ADMIN=2019
```

Copy the `.env` to both servers (or use your preferred secret sync method).

### 2. Bootstrap Media Server

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
- Create required directories
- Restore Immich / Jellyfin backups if present
- Symlink `.env` into every service
- Pull, build and start the entire Media stack

### 3. Bootstrap AI Server

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

# Enter a container
docker exec -it ollama bash

# Pull a new Ollama model
docker exec -it ollama ollama pull qwen2.5-coder:7b
```
---

# Making Updates to .env File
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

---

## Design Principles

- **Everything as Code** – no manual container configuration
- **Idempotent scripts** – safe to re-run
- **Single source of truth** – one shared `.env` (symlinked)
- **Separation of concerns** – Media and AI stacks are independent
- **Secure by default** – Tailscale for private access, Caddy for public TLS

---

## License

Private repository – for personal use.
```
