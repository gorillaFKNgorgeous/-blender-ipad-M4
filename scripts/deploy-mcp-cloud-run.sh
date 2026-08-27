#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_DIR="$(dirname "$SCRIPT_DIR")"
SERVICE_NAME="${GHOSTBLENDER_SERVICE_NAME:-ghostblender-mcp}"
REGION="${GHOSTBLENDER_REGION:-australia-southeast1}"
PROJECT_ID="${GHOSTBLENDER_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "Select a Google Cloud project first: gcloud config set project PROJECT_ID" >&2
  exit 1
fi

for command_name in curl gcloud jq openssl; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done

device_token="${GHOSTBLENDER_DEVICE_TOKEN:-$(openssl rand -hex 32)}"
mcp_path_token="${GHOSTBLENDER_MCP_PATH_TOKEN:-$(openssl rand -hex 32)}"
runtime_service_account="$SERVICE_NAME@$PROJECT_ID.iam.gserviceaccount.com"

gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  secretmanager.googleapis.com \
  --project "$PROJECT_ID"

if ! gcloud iam service-accounts describe "$runtime_service_account" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SERVICE_NAME" \
    --project "$PROJECT_ID" \
    --display-name "GhostBlender MCP runtime"
fi

ensure_secret() {
  local secret_name="$1"
  local secret_value="$2"
  if ! gcloud secrets describe "$secret_name" --project "$PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$secret_name" --project "$PROJECT_ID" --replication-policy automatic
  fi
  printf '%s' "$secret_value" | \
    gcloud secrets versions add "$secret_name" --project "$PROJECT_ID" --data-file=- >/dev/null
  gcloud secrets add-iam-policy-binding "$secret_name" \
    --project "$PROJECT_ID" \
    --member "serviceAccount:$runtime_service_account" \
    --role roles/secretmanager.secretAccessor >/dev/null
}

ensure_secret ghostblender-device-token "$device_token"
ensure_secret ghostblender-mcp-path-token "$mcp_path_token"

gcloud run deploy "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --source "$HARNESS_DIR/mcp-server" \
  --service-account "$runtime_service_account" \
  --set-secrets DEVICE_TOKEN=ghostblender-device-token:latest,MCP_PATH_TOKEN=ghostblender-mcp-path-token:latest \
  --allow-unauthenticated \
  --max-instances 1 \
  --concurrency 40 \
  --timeout 300 \
  --quiet

service_url="$(gcloud run services describe "$SERVICE_NAME" \
  --project "$PROJECT_ID" \
  --region "$REGION" \
  --format 'value(status.url)')"

health_json="$(curl --fail --silent --show-error "$service_url/healthz")"
jq -e '.service == "ghostblender-mcp" and .version == "0.1.0"' <<<"$health_json" >/dev/null

mcp_json="$(curl --fail --silent --show-error \
  --request POST \
  --header 'accept: application/json, text/event-stream' \
  --header 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cloud-run-deploy-check","version":"0.1.0"}}}' \
  "$service_url/mcp/$mcp_path_token")"
jq -e '.result.serverInfo.name == "ghostblender-ipad"' <<<"$mcp_json" >/dev/null

umask 077
output_path="$HARNESS_DIR/ghostblender-mcp-connection.txt"
{
  echo "BLENDER_SERVER=$service_url"
  echo "BLENDER_DEVICE_TOKEN=$device_token"
  echo "CHATGPT_MCP_URL=$service_url/mcp/$mcp_path_token"
} > "$output_path"

echo "GhostBlender MCP deployed."
echo "Health and MCP initialization checks passed."
echo "Connection details were written to: $output_path"
echo "Keep that file private; it contains the device token and private MCP capability URL."
