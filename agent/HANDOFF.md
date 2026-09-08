# GhostBlender live MCP implementation — working handoff
Updated 2026-09-08. Status: implementation in progress; no live device connection claimed.

## Objective
Persistent authenticated OpenAI/ChatGPT access to the running iPad Blender 5.2 scene: inspection, arbitrary Blender Python, images, diagnostics, managed scripts, autonomous iteration. One-time installation/pairing is unavoidable; no repeated manual code/log transfer.

## Verified baseline and constraints
- Repository: gorillaFKNgorgeous/-blender-ipad-M4. Initial main: bb977ea0a16d0f09942ca04b5b59270042c46461.
- Work directly on main; no branches or PRs. Old MCP prototype is explicitly rejected; do not restore it.
- Installed working baseline: build 81. Scene partial library write crash remains unresolved. Do not use bpy.data.libraries.write(Scene) for bridge checkpoints.
- Blender pin: 2bc556e58e82eb3a801895f2cb1881c0267e5cd5; CPython 3.13.13; Xcode 26.3.
- Current source already copies PartialWriteContext colorspace; prior contrary diagnosis was wrong.
- Attached Apple/Siri architecture is background, not verified implementation authority. Do not initialize a second Python interpreter or use removed PyEval_InitThreads.
- No paid API invocation or cloud hosting started.

## Architecture decisions
- Outbound HTTPS device exchange with a relay. Remote MCP exposed by relay. No public iPad listener, port forwarding, desktop subprocess, or Python network threads.
- Native NSURLSession network transport, exposed as a built-in Python module through existing bpy_internal_modules. A persistent bpy.app.timers dispatcher owns ALL bpy access.
- Foreground only; preserve pairing and reconnect on reopen/network change. iPadOS can suspend the app; no always-running-background claim.
- Unique idempotency keys, scene/session binding, bounded queues/payloads, durable command journal. Never replay an uncertain mutation automatically.
- Full Python is explicitly privileged, not an AST security sandbox. Device disconnect control.
- Capture returns actual image bytes to MCP. Diagnostics include recent command outcomes, build/session data and app file logs.
- Server authentication must match the client: ChatGPT developer-mode currently documents OAuth; OpenAI Responses supports an authorization token. Do not present a bearer-only endpoint as ChatGPT-ready.

## Checklist
- [x] Read attachment and project status; locate and clone repository.
- [x] Inspect pinned Python module registration and startup loader.
- [x] Verify OpenAI remote MCP client requirements.
- [ ] Implement native transport, runtime dispatcher, startup/pairing UI.
- [ ] Implement authenticated MCP relay with durable jobs.
- [ ] Test protocol/reconnect/idempotency/scene changes/security bounds.
- [ ] Integrate source transform and packaging checks; run exact pinned transform checks.
- [ ] Commit complete reviewed implementation on main and inspect CI.
- [ ] Deploy relay to an authorized persistent host.
- [ ] Install new signed IPA and pair device; attach MCP to client.
- [ ] Prove live scene inspect → edit → image → refine, logs, and reconnect.
- [ ] Update this handoff with exact commit/build/endpoint and remaining blockers.

## Sources
- https://developers.openai.com/api/docs/guides/developer-mode
- https://developers.openai.com/api/docs/guides/tools-connectors-mcp
- https://modelcontextprotocol.io/specification/2025-11-25/basic/transports
- https://github.com/ahujasid/blender-mcp (community project, not verified as Blender Foundation release)
- https://developer.apple.com/documentation/foundation/urlsession
