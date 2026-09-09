# SPDX-License-Identifier: GPL-2.0-or-later
"""Single-owner OAuth authorization code + S256 PKCE, with pre-registered client.

TLS termination is mandatory. Tokens are stored as SHA-256 digests; a change of
owner/client secret invalidates all issued tokens. No dynamic registration.
"""
import base64
import hashlib
import hmac
import html
import re
import secrets
import time
from urllib.parse import urlencode


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def same(a, b):
    return isinstance(a, str) and isinstance(b, str) and hmac.compare_digest(a.encode(), b.encode())


def short_digest(value):
    return digest(value)[:12] if isinstance(value, str) else 'not-a-string'


class OAuth:
    def __init__(self, store, origin, client_id, client_secret, owner_key, redirects):
        self.store, self.origin = store, origin
        self.client_id, self.client_secret, self.owner_key = client_id, client_secret, owner_key
        self.redirects = set(redirects)
        self.resource = origin + '/mcp'
        self.revision = digest(client_secret + '\n' + owner_key)

    def metadata(self):
        return {'issuer': self.origin, 'authorization_response_iss_parameter_supported': True,
                'authorization_endpoint': self.origin + '/authorize',
                'token_endpoint': self.origin + '/token',
                'response_types_supported': ['code'], 'grant_types_supported': ['authorization_code','refresh_token'],
                'token_endpoint_auth_methods_supported': ['none','client_secret_post','client_secret_basic'],
                'code_challenge_methods_supported': ['S256'], 'scopes_supported': ['blender']}

    def resource_metadata(self):
        return {'resource': self.resource, 'authorization_servers': [self.origin],
                'scopes_supported': ['blender'], 'bearer_methods_supported': ['header']}

    def authorize_form(self, params):
        if (params.get('client_id') != self.client_id or params.get('response_type') != 'code'
                or params.get('redirect_uri') not in self.redirects
                or params.get('code_challenge_method') != 'S256'
                or not re.fullmatch(r'[A-Za-z0-9_-]{43}', params.get('code_challenge', ''))
                or params.get('resource') != self.resource
                or params.get('scope', 'blender') != 'blender'):
            raise ValueError('invalid_authorization_request')
        ticket = secrets.token_urlsafe(32)
        self.store.put_oauth(digest(ticket), 'pending', params, time.time() + 600)
        return f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Connect GhostBlender</title><style>body{{font:18px system-ui;background:#11141b;color:#edf2ff;max-width:34rem;margin:8vh auto;padding:24px}}input,button{{font:inherit;width:100%;box-sizing:border-box;padding:14px;margin:12px 0}}button{{background:#78d7cb;color:#071915;border:0;border-radius:8px}}</style>
<h1>Connect GhostBlender</h1><p>Allow this agent to inspect the live scene, run Blender Python, capture images, read diagnostics and edit scripts.</p>
<p>Python access can change your project and app files. You can disconnect the agent inside GhostBlender.</p>
<form method="post" action="/authorize" autocomplete="off"><input type="hidden" name="ticket" value="{html.escape(ticket)}">
<label for="key">Owner connection key</label><input id="key" type="text" name="owner_key" autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false" inputmode="text" required>
<p><small>The key is intentionally shown while entering it so iPad password autofill cannot silently replace the pasted value.</small></p>
<button type="submit">Authorize connection</button></form></html>'''

    def approve(self, ticket, owner_key):
        # Ignore accidental surrounding whitespace from clipboard/input handling,
        # but keep the credential comparison exact otherwise. On mismatch expose
        # only length and a short SHA-256 fingerprint so browser-vs-server
        # transformation can be diagnosed without returning the secret itself.
        submitted = owner_key.strip() if isinstance(owner_key, str) else owner_key
        # Some chat/Markdown copy paths expose underscores as ``\_``. Accept
        # that one presentation-only escape only when the resulting credential
        # still matches the configured owner key exactly.
        if isinstance(submitted, str) and not same(submitted, self.owner_key):
            unescaped = submitted.replace(r'\_', '_')
            if same(unescaped, self.owner_key):
                submitted = unescaped
        if not same(submitted, self.owner_key):
            submitted_len = len(submitted) if isinstance(submitted, str) else -1
            raise ValueError(
                'invalid_owner_key '
                f'submitted_len={submitted_len} expected_len={len(self.owner_key)} '
                f'submitted_sha12={short_digest(submitted)} expected_sha12={short_digest(self.owner_key)}'
            )

        ticket_key = digest(ticket)

        # A mobile browser can submit the consent form twice before the first 303
        # navigation visibly completes. Preserve the successful redirect briefly
        # so a duplicate submit returns the same authorization response instead of
        # overwriting it with authorization_expired.
        approved = self.store.get_oauth(ticket_key, 'approved')
        if approved and approved.get('revision') == self.revision and isinstance(approved.get('target'), str):
            return approved['target']

        params = self.store.get_oauth(ticket_key, 'pending')
        if not params:
            raise ValueError('authorization_expired')

        code = secrets.token_urlsafe(32)
        params['revision'] = self.revision
        self.store.put_oauth(digest(code), 'code', params, time.time() + 120)
        query = {'code': code, 'iss': self.origin}
        if 'state' in params:
            query['state'] = params['state']
        target = params['redirect_uri'] + ('&' if '?' in params['redirect_uri'] else '?') + urlencode(query)

        # Replacing pending with approved makes the ticket one-way while still
        # allowing an accidental duplicate form POST to replay only the same 303.
        self.store.put_oauth(ticket_key, 'approved', {'target': target, 'revision': self.revision}, time.time() + 120)
        return target

    def token(self, params):
        # Authorization-code and refresh grants are bound to this client below;
        # the code grant is additionally protected by S256 PKCE. Support
        # ChatGPT as an OAuth public client (`none`) and tolerate a stale static
        # secret retained by an existing app registration.
        if not same(params.get('client_id'), self.client_id):
            raise ValueError('invalid_client')
        if params.get('resource') != self.resource:
            raise ValueError('invalid_target')
        grant = params.get('grant_type')
        if grant == 'authorization_code':
            record = self.store.get_oauth(digest(params.get('code','')), 'code', consume=True)
            verifier = params.get('code_verifier', '')
            if not re.fullmatch(r'[A-Za-z0-9._~-]{43,128}', verifier):
                raise ValueError('invalid_grant')
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
            if (not record or record.get('revision') != self.revision or record['client_id'] != self.client_id
                    or record['redirect_uri'] != params.get('redirect_uri')
                    or not same(record['code_challenge'], challenge)):
                raise ValueError('invalid_grant')
        elif grant == 'refresh_token':
            record = self.store.get_oauth(digest(params.get('refresh_token','')), 'refresh', consume=True)
            if not record or record.get('revision') != self.revision or record['client_id'] != self.client_id:
                raise ValueError('invalid_grant')
        else:
            raise ValueError('unsupported_grant_type')
        record = {'client_id': self.client_id, 'resource': self.resource, 'revision': self.revision}
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        self.store.put_oauth(digest(access), 'access', record, time.time() + 3600)
        self.store.put_oauth(digest(refresh), 'refresh', record, time.time() + 30*86400)
        return {'access_token': access, 'refresh_token': refresh, 'token_type': 'Bearer',
                'expires_in': 3600, 'scope': 'blender'}

    def authenticate(self, token):
        record = self.store.get_oauth(digest(token), 'access')
        return bool(record and record.get('resource') == self.resource and record.get('revision') == self.revision)
