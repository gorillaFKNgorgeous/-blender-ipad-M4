#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Print the only values needed to connect the private GhostBlender MCP bridge.
# Automatically finds the existing relay VM zone.
set -Eeuo pipefail

VM="${GHOSTBLENDER_VM:-ghostblender-relay}"
PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
if [[ -z "$PROJECT" || "$PROJECT" == "(unset)" ]]; then
  echo "No Google Cloud project selected. Run: gcloud config set project ghostblender-relay" >&2
  exit 1
fi

ZONE="$(gcloud compute instances list \
  --project "$PROJECT" \
  --filter="name=($VM)" \
  --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')"
if [[ -z "$ZONE" ]]; then
  echo "Could not find VM $VM in project $PROJECT." >&2
  exit 1
fi

echo "Relay VM zone: $ZONE" >&2

gcloud compute ssh "$VM" \
  --project "$PROJECT" \
  --zone "$ZONE" \
  --tunnel-through-iap \
  --quiet \
  --command 'cd ~/ghostblender/agent/relay && \
    ORIGIN=$(sed -n "s/^PUBLIC_ORIGIN=//p" .env) && \
    AGENT=$(sed -n "s/^AGENT_TOKEN=//p" .env) && \
    DEVICE_ID=$(sed -n "s/^DEVICE_ID=//p" .env) && \
    DEVICE_TOKEN=$(sed -n "s/^DEVICE_TOKEN=//p" .env) && \
    printf "MCP_URL=%s/mcp/%s\nDEVICE_ID=%s\nDEVICE_TOKEN=%s\n" "$ORIGIN" "$AGENT" "$DEVICE_ID" "$DEVICE_TOKEN"'
