#!/usr/bin/env bash
set -euo pipefail

APIM_HOST="${APIM_HOST:-localhost}"
APIM_HTTPS_PORT="${APIM_HTTPS_PORT:-9443}"
APIM_ENV_NAME="${APIM_ENV_NAME:-dev}"
APIM_USERNAME="${APIM_USERNAME:-admin}"
APIM_PASSWORD="${APIM_PASSWORD:-admin}"
PROJECT_ROOT="${PROJECT_ROOT:-.}"

APIM_URL="https://${APIM_HOST}:${APIM_HTTPS_PORT}"

echo "[deploy-apim] Syncing OpenAPI definitions..."
for api in AccountBalanceAPI CustomerProxyAPI LoanEligibilityAPI; do
  src="${PROJECT_ROOT}/src/main/wso2mi/resources/api-definitions/${api}.yaml"
  dst="${PROJECT_ROOT}/apim/apis/${api}/Definitions/swagger.yaml"
  if [ ! -f "$src" ]; then
    echo "[deploy-apim] ERROR: source definition not found: $src"
    exit 1
  fi
  cp "$src" "$dst"
  echo "[deploy-apim]   Copied $api definition."
done

echo "[deploy-apim] Adding apictl environment: $APIM_ENV_NAME → $APIM_URL"
apictl add env "$APIM_ENV_NAME" --apim "$APIM_URL" 2>/dev/null || true

echo "[deploy-apim] Logging in to $APIM_ENV_NAME ..."
apictl login "$APIM_ENV_NAME" \
  --username "$APIM_USERNAME" \
  --password "$APIM_PASSWORD" \
  --insecure

FAILED_APIS=()

import_api() {
  local api_name="$1"
  local api_dir="${PROJECT_ROOT}/apim/apis/${api_name}"

  echo "[deploy-apim] Importing $api_name ..."
  if apictl import api \
      --file "$api_dir" \
      --environment "$APIM_ENV_NAME" \
      --update \
      --insecure; then
    echo "[deploy-apim]   $api_name → OK"
  else
    echo "[deploy-apim]   $api_name → FAILED"
    FAILED_APIS+=("$api_name")
  fi
}

import_api "AccountBalanceAPI"
import_api "CustomerProxyAPI"
import_api "LoanEligibilityAPI"

if [ ${#FAILED_APIS[@]} -gt 0 ]; then
  echo "[deploy-apim] ERROR: the following API imports failed: ${FAILED_APIS[*]}"
  exit 1
fi

echo "[deploy-apim] All three APIs imported successfully."

PRODUCT_DIR="${PROJECT_ROOT}/apim/api-products/JamiiiBankingPlatform"
echo "[deploy-apim] Importing API Product: JamiiiBankingPlatform ..."
if apictl import api-product \
    --file "$PRODUCT_DIR" \
    --environment "$APIM_ENV_NAME" \
    --update \
    --insecure; then
  echo "[deploy-apim]   JamiiiBankingPlatform → OK"
else
  echo "[deploy-apim] ERROR: API Product import failed"
  exit 1
fi

echo "[deploy-apim] Done."
