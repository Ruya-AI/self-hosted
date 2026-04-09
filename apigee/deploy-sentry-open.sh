#!/bin/bash
# Deploy the sentry-open Apigee proxy to the ruya-api-gateway organization.
#
# Prerequisites:
#   - gcloud auth login
#   - Firewall rule allowing Apigee (10.76.104.0/22) to reach Sentry VM (10.128.0.4:9000)
#
# Usage: ./apigee/deploy-sentry-open.sh

set -euo pipefail

ORG="ruya-api-gateway"
PROXY="sentry-open"
ENV="prod"
BUNDLE_DIR="$(cd "$(dirname "$0")/$PROXY" && pwd)"
TOKEN=$(gcloud auth print-access-token)
API_BASE="https://apigee.googleapis.com/v1/organizations/$ORG"

echo "=== Packaging proxy bundle ==="
cd "$BUNDLE_DIR"
rm -f /tmp/sentry-open-bundle.zip
zip -r /tmp/sentry-open-bundle.zip apiproxy/

echo ""
echo "=== Uploading proxy to Apigee ==="
UPLOAD_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE/apis?name=$PROXY&action=import" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @/tmp/sentry-open-bundle.zip)

HTTP_CODE=$(echo "$UPLOAD_RESPONSE" | tail -1)
BODY=$(echo "$UPLOAD_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -ge 400 ]; then
    echo "Upload failed (HTTP $HTTP_CODE):"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
fi

REVISION=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['revision'])")
echo "Uploaded revision: $REVISION"

echo ""
echo "=== Deploying revision $REVISION to $ENV ==="
DEPLOY_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "$API_BASE/environments/$ENV/apis/$PROXY/revisions/$REVISION/deployments?override=true" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Length: 0")

HTTP_CODE=$(echo "$DEPLOY_RESPONSE" | tail -1)
BODY=$(echo "$DEPLOY_RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -ge 400 ]; then
    echo "Deploy failed (HTTP $HTTP_CODE):"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    exit 1
fi

echo "Deployed successfully!"
echo ""
echo "=== DSN format ==="
echo "https://<PUBLIC_KEY>@api.ruya.ai/open/sentry/<PROJECT_ID>"
echo ""
echo "Done! Sentry ingestion available at: https://api.ruya.ai/open/sentry/"
