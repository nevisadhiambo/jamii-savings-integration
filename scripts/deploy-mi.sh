#!/usr/bin/env bash
# deploy-mi.sh – deploy the MI Carbon Application to a running MI instance.
#
# Environment variables (with defaults for docker-compose dev):
#   MI_HOST        – MI management API host   (default: localhost)
#   MI_MGMT_PORT   – MI management API port   (default: 9164)
#   MI_USERNAME    – MI admin username         (default: admin)
#   MI_PASSWORD    – MI admin password         (default: admin)
#   CAR_FILE       – path to the .car artifact (required)
#
# The MI Management API supports uploading a CAR via:
#   POST /management/application
set -euo pipefail

MI_HOST="${MI_HOST:-localhost}"
MI_MGMT_PORT="${MI_MGMT_PORT:-9164}"
MI_USERNAME="${MI_USERNAME:-admin}"
MI_PASSWORD="${MI_PASSWORD:-admin}"
CAR_FILE="${CAR_FILE:?CAR_FILE must be set}"

if [ ! -f "$CAR_FILE" ]; then
  echo "[deploy-mi] ERROR: CAR file not found: $CAR_FILE"
  exit 1
fi

CAR_NAME=$(basename "$CAR_FILE")
echo "[deploy-mi] Deploying $CAR_NAME to http://${MI_HOST}:${MI_MGMT_PORT} ..."

HTTP_STATUS=$(curl -s -o /tmp/mi-deploy-response.json -w "%{http_code}" \
  -u "${MI_USERNAME}:${MI_PASSWORD}" \
  -X POST "http://${MI_HOST}:${MI_MGMT_PORT}/management/application" \
  -F "file=@${CAR_FILE}")

BODY=$(cat /tmp/mi-deploy-response.json)
echo "[deploy-mi] HTTP status: $HTTP_STATUS"
echo "[deploy-mi] Response:    $BODY"

if [ "$HTTP_STATUS" -ne 200 ] && [ "$HTTP_STATUS" -ne 201 ]; then
  echo "[deploy-mi] ERROR: deployment failed (HTTP $HTTP_STATUS)"
  exit 1
fi

echo "[deploy-mi] Deployment successful."
