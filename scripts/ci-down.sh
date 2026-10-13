#!/usr/bin/env bash
# ci-down.sh – tear down the docker-compose stack (always runs, even on failure).
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

echo "[ci-down] Stopping Jamii integration stack..."
docker compose -f "$COMPOSE_FILE" down --remove-orphans --volumes || true
echo "[ci-down] Stack stopped."
