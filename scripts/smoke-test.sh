#!/usr/bin/env bash
# smoke-test.sh – lightweight post-deploy smoke tests for all three APIs.
# Exits non-zero if any check fails (pipeline treats this as a test failure).
set -euo pipefail

MI_HOST="${MI_HOST:-localhost}"
MI_HTTP_PORT="${MI_HTTP_PORT:-8290}"
BASE="http://${MI_HOST}:${MI_HTTP_PORT}"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local url="$2"
  local method="${3:-GET}"
  local body="${4:-}"
  local expect_status="${5:-200}"

  if [ -n "$body" ]; then
    actual=$(curl -s -o /tmp/smoke-resp.json -w "%{http_code}" \
      -X "$method" "$url" \
      -H "Content-Type: application/json" \
      -d "$body")
  else
    actual=$(curl -s -o /tmp/smoke-resp.json -w "%{http_code}" \
      -X "$method" "$url")
  fi

  if [ "$actual" = "$expect_status" ]; then
    echo "[smoke] PASS  [$actual] $desc"
    PASS=$((PASS + 1))
  else
    echo "[smoke] FAIL  [got=$actual expect=$expect_status] $desc"
    echo "        Response: $(cat /tmp/smoke-resp.json)"
    FAIL=$((FAIL + 1))
  fi
}

echo "[smoke] Running smoke tests against $BASE ..."

# AccountBalanceAPI – valid account
check "AccountBalanceAPI – valid account ACC001" \
  "${BASE}/accounts/ACC001/balance" GET "" 200

# AccountBalanceAPI – unknown account (expect 404)
check "AccountBalanceAPI – unknown account" \
  "${BASE}/accounts/UNKNOWN999/balance" GET "" 404

# CustomerProxyAPI – valid customer id 1
check "CustomerProxyAPI – customer id 1" \
  "${BASE}/customers/1" GET "" 200

# LoanEligibilityAPI – valid eligibility check
check "LoanEligibilityAPI – eligibility check" \
  "${BASE}/loans/check-eligibility" POST \
  '{"applicantName":"Test User","amount":50000,"termMonths":12}' \
  200

echo ""
echo "[smoke] Results: ${PASS} passed, ${FAIL} failed"

if [ $FAIL -gt 0 ]; then
  exit 1
fi
