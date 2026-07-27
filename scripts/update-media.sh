#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Starting Docker Stack Updates ==="

# Find all unique working directories that contain a docker-compose.yml file
# Adjust the search path below if your compose files are stored elsewhere (e.g., /opt or /home)
COMPOSE_DIRS=$(docker ps --format "{{.Label \"com.docker.compose.project.working_dir\"}}" | grep -v '^$' | sort -u)

if [ -z "$COMPOSE_DIRS" ]; then
    echo "No Docker Compose projects found via labels. Falling back to manual directory checks..."
    # Add explicit paths here if needed, e.g., COMPOSE_DIRS="/path/to/immich /path/to/other-app"
fi

for dir in $COMPOSE_DIRS; do
    echo "--------------------------------------------------"
    echo "Updating stack in directory: $dir"
    echo "--------------------------------------------------"
    
    cd "$dir"
    
    # Pull the latest images specified in the compose file
    docker compose pull
    
    # Recreate containers with the new images, leaving volumes/config intact
    docker compose up -d
    
    echo "Successfully updated stack at $dir"
    echo ""
done

echo "=== Cleaning up dangling images ==="
docker image prune -f

echo "=== All updates complete! ==="