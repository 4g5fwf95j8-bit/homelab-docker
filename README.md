# Homelab Docker Setup

Two-laptop homelab using Docker Compose.

- **Laptop 1 (Media Server)**: Jellyfin, Immich, Homepage, Caddy + DuckDNS, PriceBuddy, Tailscale
- **Laptop 2 (AI Server)**: Ollama + Open WebUI

## Repository Structure
.
├── laptop1/                    # Main compose file for media server
├── laptop2/                    # Compose file for AI server
├── services/                   # Modular service definitions from base repo
├── scripts/                    # Setup and maintenance scripts
├── configtemplates/            # Config templates (samba, snapraid, etc.)
├── .env                        # Environment variables (gitignored)
├── .gitignore
└── README.md


## Quick Start

1. Make sure the external drive is mounted at `/mnt/seagate_storage`
2. Update `.env` with your secrets and paths
3. Run the setup scripts:

cd /opt/docker/homelab-docker

sudo ./scripts/setup-laptop-media.sh   # Laptop 1
sudo ./scripts/setup-laptop-ai.sh      # Laptop 2

# Common Commands
## Start / Restart Services
cd /opt/docker/homelab-docker/laptop1
docker compose up -d

# Update All Services
cd /opt/docker/homelab-docker/laptop1
docker compose pull && docker compose up -d

# View Logs
docker compose logs -f

# Check Running Containers
docker ps

# Maintenance
# Prune unused images/containers
docker system prune -f

# Backup script (if available)
./scripts/backup.sh


# Adding a New App / Service
1. Find or create a compose definition in services/
2. Add the service to laptop1/docker-compose.yml or laptop2/docker-compose.yml
3. Add any required variables to .env
4. Re-run the relevant setup script or docker compose up -d

# Architecture Notes
- All services share the root .env file via symlinks (run-each-update.sh)
- Media and photo library stored on external drive (/mnt/seagate_storage)
- Caddy provides reverse proxy with DuckDNS subdomains
- Tailscale for secure remote access and SSH
- Migration-friendly: reuses existing /opt/immich, /opt/jellyfin, and media folders

# Important Paths
- Media: /mnt/seagate_storage/jellyfin/media
- Immich Library: /mnt/seagate_storage/immich
- Configs: /opt/jellyfin, /opt/immich
