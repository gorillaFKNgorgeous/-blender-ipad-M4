# GhostBlender MCP

This directory contains the private MCP relay used by Blender on iPad. ChatGPT
speaks MCP Streamable HTTP to the relay, while the Blender startup bridge makes
an authenticated outbound HTTPS long-poll connection using only Python's
standard library.

The first release intentionally exposes only named Blender operations. It does
not expose arbitrary Python execution or an inbound iPad port.

## Local test

```bash
npm install
npm test
DEVICE_TOKEN=local-device-token-change-me \
MCP_PATH_TOKEN=local-mcp-path-change-me \
npm start
```

The local MCP URL is:

```text
http://localhost:8080/mcp/local-mcp-path-change-me
```

## Cloud Run deployment

From an authenticated Google Cloud Shell at the repository root:

```bash
bash ./scripts/deploy-mcp-cloud-run.sh
```

The script enables the required APIs, creates a least-purpose runtime service
account, stores both generated tokens in Secret Manager, deploys one Cloud Run
instance, and writes the three private connection values to
`ghostblender-mcp-connection.txt`. Never commit that file.

Cloud Run must remain limited to one instance until the in-memory command broker
is replaced with durable shared state.

## ChatGPT Developer Mode

Use the `CHATGPT_MCP_URL` value as a no-authentication developer-mode MCP
connection. The unguessable path is a temporary capability credential. Keep the
connection private. OAuth 2.1 is required before any public or multi-user use.

## Blender iPad

The build installs `blender/ghostblender_bridge.py` as a startup script. Open
the 3D View sidebar, choose **GhostBlender**, enter `BLENDER_SERVER` and
`BLENDER_DEVICE_TOKEN`, then press **Connect GhostBlender**.

The device token is stored only inside Blender's iPad application sandbox, not
inside `.blend` files.
