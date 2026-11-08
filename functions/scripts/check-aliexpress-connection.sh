#!/usr/bin/env bash
# Checks marketplace_connections/aliexpress status via the deployed
# aliexpressConnectionStatus function (reads Firestore server-side).
#
# Usage:
#   PRODUCT_IMPORT_API_KEY=your_key ./check-aliexpress-connection.sh
# or export it once in your shell profile.

set -euo pipefail

PROJECT_ID="chalakchar-mart"
REGION="asia-south1"
URL="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/aliexpressConnectionStatus"

if [ -z "${PRODUCT_IMPORT_API_KEY:-}" ]; then
  echo "Set PRODUCT_IMPORT_API_KEY in your environment first:" >&2
  echo "  export PRODUCT_IMPORT_API_KEY=\$(firebase functions:secrets:access PRODUCT_IMPORT_API_KEY)" >&2
  exit 1
fi

curl -sS -H "x-import-api-key: ${PRODUCT_IMPORT_API_KEY}" "$URL" | python3 -m json.tool 2>/dev/null \
  || curl -sS -H "x-import-api-key: ${PRODUCT_IMPORT_API_KEY}" "$URL"
