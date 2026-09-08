#!/usr/bin/env python3
"""Create local relay credentials without printing secrets. Never commit .env."""
import argparse
import json
import os
from pathlib import Path
import secrets
from urllib.parse import urlsplit

p=argparse.ArgumentParser()
p.add_argument('--origin',required=True,help='HTTPS relay origin, no trailing slash')
p.add_argument('--redirect-uri',required=True,action='append',help='Exact callback displayed in ChatGPT app management')
p.add_argument('--output',default='.env')
a=p.parse_args()
u=urlsplit(a.origin)
if u.scheme!='https' or not u.hostname or u.path or u.query or u.fragment or u.username:
    p.error('--origin must be an HTTPS origin')
for redirect in a.redirect_uri:
    r=urlsplit(redirect)
    if r.scheme!='https' or not r.hostname or r.fragment or r.username:
        p.error('callbacks must be exact HTTPS URLs')
values={'PUBLIC_ORIGIN':a.origin,'DEVICE_ID':'ipad','OAUTH_CLIENT_ID':'ghostblender',
        'OAUTH_REDIRECT_URIS':json.dumps(a.redirect_uri,separators=(',',':'))}
for key in ('DEVICE_TOKEN','AGENT_TOKEN','OAUTH_CLIENT_SECRET','OWNER_KEY'):
    values[key]=secrets.token_urlsafe(32)
os.umask(0o077)
with open(a.output,'x',encoding='utf-8') as f:
    for k,v in values.items():
        f.write(k+'='+v+'\n')
print('Created private environment file:',Path(a.output).resolve())
print('Use DEVICE_TOKEN only on the iPad; OWNER_KEY only in the consent form.')
