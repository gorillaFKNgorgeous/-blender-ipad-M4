#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Add the exact ChatGPT developer-app callback to a relay .env safely."""

import json
from pathlib import Path
import sys
from urllib.parse import urlsplit

if len(sys.argv) != 2:
    raise SystemExit("Usage: python3 set-chatgpt-redirect.py https://chatgpt.com/connector/oauth/CALLBACK_ID")

redirect = sys.argv[1].strip()
parsed = urlsplit(redirect)
if (parsed.scheme != "https" or parsed.hostname != "chatgpt.com" or parsed.username or
        parsed.password or parsed.fragment or not parsed.path.startswith("/connector/oauth/")):
    raise SystemExit("Refusing callback: expected the exact https://chatgpt.com/connector/oauth/{callback_id} URL shown by ChatGPT")

path = Path(".env")
if not path.is_file():
    raise SystemExit("Run this from agent/relay on the deployed VM; .env was not found")

lines = path.read_text(encoding="utf-8").splitlines()
updated = []
found = False
for line in lines:
    if line.startswith("OAUTH_REDIRECT_URIS="):
        found = True
        redirects = json.loads(line.split("=", 1)[1])
        if redirect not in redirects:
            redirects.append(redirect)
        line = "OAUTH_REDIRECT_URIS=" + json.dumps(redirects, separators=(",", ":"))
    updated.append(line)
if not found:
    raise SystemExit("OAUTH_REDIRECT_URIS is missing from .env")

path.write_text("\n".join(updated) + "\n", encoding="utf-8")
print("Added exact ChatGPT callback to relay allowlist.")
print("Restart with: sudo docker-compose up -d")
