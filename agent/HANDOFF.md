# GhostBlender live MCP — resume here

Updated 2026-09-08. **Implementation and initial validation complete; live device
connection still unverified.** Do not restart this work or restore the old MCP
prototype. Read this file and `agent/README.md`, then inspect the current CI run.

## Goal and project constraints

Direct, persistent, authenticated access from ChatGPT/OpenAI to running iPad
Blender 5.2: scene inspection, Python execution, actual images, diagnostics,
script creation/modification and autonomous iteration. The user supplies goals,
not Blender operator names. One-time signed-app installation and pairing remain
necessary; the intended steady state has no manual code/log transfer.

- Repo: https://github.com/gorillaFKNgorgeous/-blender-ipad-M4
- Work on main only. No new branches or PRs. The obsolete MCP prototype is rejected.
- Initial main: bb977ea0a16d0f09942ca04b5b59270042c46461.
- Initial durable checklist: abca12cb5e2cb5342b401d71bc09e686bd9434b5.
- Initial implementation: 90e9416f7c5a0cf44443fe2eb3d33aafc866c770.
- Final integration commit/build: inspect latest main and update the run record below.
- Installed working baseline is build 81, not this new code.
- Blender source pin: 2bc556e58e82eb3a801895f2cb1881c0267e5cd5.
- CPython 3.13.13, Xcode 26.3, iPad Pro M4 16 GB; existing Signulous signing route.
- Scene partial library-write crash is unresolved. Never use Scene partial writes
  for bridge checkpoints. The source already copies PartialWriteContext colorspace;
  the prior claim it was missing was wrong. Do not reintroduce that backport.
- The Apple/Siri attachment is background, not verified implementation authority.
  No second Python interpreter, PyEval_InitThreads, speculative FoundationModels
  APIs or assumed unlimited background execution have been introduced.

## Implemented files

- `agent/native/ghostbridge_transport.mm`: asynchronous NSURLSession HTTPS,
  bounded response buffers, redirect rejection, no Python callbacks/background
  Python threads, app foreground and measured process memory status.
- `agent/runtime/__init__.py`: startup registration, persistent main-thread timer,
  one-time connection panel, saved pairing, reconnect/backoff/disconnect.
- `agent/runtime/core.py`: scene inspection, privileged Python with bounded stdout
  and cooperative Python deadline, screenshot/Render Result capture, app logs,
  persistent script workspace and durable command journal/outbox. Detects file
  loads and switches to a different active scene before executing stale commands.
- `agent/relay/{server,store,oauth}.py`: dependency-free single-owner/single-process
  MCP Streamable HTTP, SQLite jobs and OAuth state. Separate device/agent tokens,
  static OAuth client, S256 PKCE, audience/issuer binding, expiration and rotating
  refresh tokens. Correct tool annotations and MCP image content.
- `agent/relay/{Dockerfile,compose.yml,Caddyfile,configure.py}`: HTTPS + persistent
  Docker volume deployment; credentials generated locally, never committed.
- `scripts/apply-ios-agent-bridge.py`: validates exact pinned source anchors,
  adds native file/CMake frameworks/built-in registration and startup package.
- `scripts/prepare-source.sh`: invokes the transform after existing transforms.
- `scripts/package-ipa.sh`: verifies both bundled agent startup/core files.
- `.github/workflows/agent-checks.yml`: unit/protocol and official-client tests,
  plus Objective-C++ compilation against the actual iOS SDK.
- Main IPA workflow: runs agent tests before bootstrap; agent runtime/native
  changes now trigger an IPA build. Existing pins/features/entitlements preserved.

## Proven checks

- Initial CI all green: https://github.com/gorillaFKNgorgeous/-blender-ipad-M4/actions/runs/34223282161
  - Actual iOS SDK Objective-C++ syntax compilation passed (job 102051223490).
  - Official MCP Python client 1.26.0 initialization, tool discovery and call passed
    (job 102051223883). Production server does not depend on that package.
- Latest local behavior suite: 17 passed. Covers duplicate prevention, lost
  acknowledgements, persisted issued jobs, app restart journal/outbox, scene changes
  including in-file scene switching, expiry/uncertain outcomes, offline device,
  queue limits/cancellation, script traversal/symlinks/hash conflicts, Python
  time/output bounds, HTTP authentication/origin checks, image-content mapping,
  OAuth code single use, PKCE and refresh rotation.
- Existing Files transformation suite: all seven passed.
- Transform applied successfully to exact pinned bpy_interface.cc/CMakeLists.txt;
  duplicate application rejected. Upstream creator CMake installs the whole
  scripts directory, including the new startup package.
- Python compilation, shell syntax and git diff whitespace checks passed.

These tests do not prove physical-device screenshots, actual scene execution,
network foreground transitions, or a successfully linked/installed IPA.

## Required next actions

- [x] Preserve implementation directly on main and keep this handoff current.
- [x] Implement device runtime, authenticated relay and deployment configuration.
- [x] Validate protocol, journal and source-transform logic.
- [x] Pass initial iOS SDK syntax and independent official MCP-client CI checks.
- [ ] Inspect the final integration CI / full IPA build result; fix actual failures.
- [ ] Select and access a persistent HTTPS host. No hosting account/domain was
      provisioned and no service/API/model spending was started. Do not run this
      SQLite relay on ephemeral Cloud Run/Functions storage or multiple replicas.
      Existing Google Cloud services are mentioned in project history, but no
      authenticated Google Cloud deployment capability is available in this turn.
      A serverless host needs a durable shared backend adaptation.
- [ ] Deploy with a durable volume and generate distinct credentials using
      `configure.py`. Verify endpoint authentication before pairing the iPad.
- [ ] Install the new Signulous-profile IPA on the physical iPad.
- [ ] Pair via GhostBlender → Agent Connection, then create/authorize the ChatGPT
      developer app for /mcp using static OAuth credentials. The exact displayed
      ChatGPT redirect must match the allowlist. Issuer identification is supported.
- [ ] Execute the acceptance sequence in agent/README.md: inspect → edit → capture
      → refine, scripts, error diagnostics, scene switch, network drop/reconnect,
      app reopen, suspension, normal Files behavior. Record actual evidence.

The currently running ChatGPT session has no GhostBlender MCP tool registered.
Do not claim live access, successful on-device images, automatic IPA installation,
or background autonomy until those are observed. The bridge can persist, but
active model work still follows client run/usage/approval limits. iPadOS can
suspend an inactive app. Native Blender calls cannot be forcibly cancelled; a
failed/uncertain edit may have changed the scene and must be inspected before retry.

## Relevant current documentation

- https://developers.openai.com/api/docs/guides/developer-mode
- https://developers.openai.com/plugins/build/auth
- https://developers.openai.com/api/docs/guides/tools-connectors-mcp
- https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- https://github.com/ahujasid/blender-mcp (community project; not an established
  Blender Foundation release and not the rejected earlier project prototype)
- https://developer.apple.com/documentation/foundation/urlsession
- https://developers.openai.com/api/docs/guides/secure-mcp-tunnels — an alternative
  OpenAI-managed ingress path; requires Platform tunnel identity/runtime key and
  a running tunnel-client host. No verified iPadOS tunnel-client packaging was
  established. Do not assume it removes every host/device integration requirement.

## Run record

Initial validation passed. Final integration build record will be appended once
GitHub assigns the run ID. Refresh GitHub before reporting its status.
