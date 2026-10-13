#!/usr/bin/env bash
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"
TIMEOUT="${STACK_STARTUP_TIMEOUT:-300}"

echo "[ci-up] Starting stack..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

echo "[ci-up] Waiting up to ${TIMEOUT}s for healthy state..."
elapsed=0
interval=10

until docker compose -f "$COMPOSE_FILE" ps --format json \
      | python3 -c "
import sys, json
services = [json.loads(l) for l in sys.stdin if l.strip()]
unhealthy = [s['Name'] for s in services if s.get('Health','') not in ('healthy','')]
print('\n'.join(unhealthy))
" | grep -q .; do
  sleep $interval
  elapsed=$((elapsed + interval))
  if [ $elapsed -ge $TIMEOUT ]; then
    echo "[ci-up] ERROR: stack did not become healthy within ${TIMEOUT}s"
    docker compose -f "$COMPOSE_FILE" logs --tail=50
    exit 1
  fi
  echo "[ci-up] Waiting... (${elapsed}s elapsed)"
done

all_healthy=true
for svc in mysql mi apim; do
  state=$(docker inspect --format='{{.State.Health.Status}}' "jamii-${svc}" 2>/dev/null || echo "missing")
  echo "[ci-up] $svc → $state"
  [ "$state" = "healthy" ] || all_healthy=false
done

if [ "$all_healthy" = "false" ]; then
  echo "[ci-up] ERROR: one or more services are not healthy"
  docker compose -f "$COMPOSE_FILE" logs --tail=80
  exit 1
fi

echo "[ci-up] All services healthy."
