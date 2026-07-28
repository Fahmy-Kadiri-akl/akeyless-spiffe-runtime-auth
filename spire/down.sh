#!/usr/bin/env bash
# Stop the dev SPIRE topology and remove its containers and volumes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Stopping containers and removing volumes ..."
docker compose --project-directory "$ROOT" -f spire/docker-compose.yml down -v --remove-orphans
echo "==> Done. The dev CA and keys lived in the removed volumes; a fresh trust"
echo "    root is created on the next spire/up.sh."
