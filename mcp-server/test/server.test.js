import assert from "node:assert/strict";
import { once } from "node:events";
import test from "node:test";

import { CommandBroker, createGhostBlenderHttpServer } from "../server.js";

test("command broker completes a device round trip", async () => {
  const broker = new CommandBroker({ onlineWindowMs: 1_000 });
  broker.touch("Test iPad");

  const pendingCall = broker.call("scene_summary", {});
  const command = await broker.poll(10, "Test iPad");
  assert.equal(command.type, "scene_summary");
  assert.equal(broker.acceptResult({ id: command.id, ok: true, result: { objects: 3 } }), true);
  assert.deepEqual(await pendingCall, { objects: 3 });
});

test("HTTP service protects device endpoints and exposes MCP initialize", async (t) => {
  const deviceToken = "device-token-device-token-device-token";
  const mcpPathToken = "mcp-path-token-mcp-path-token-mcp-path-token";
  const { httpServer, mcpPath } = createGhostBlenderHttpServer({ deviceToken, mcpPathToken });
  httpServer.listen(0, "127.0.0.1");
  await once(httpServer, "listening");
  t.after(() => httpServer.close());

  const address = httpServer.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;

  const unauthorized = await fetch(`${baseUrl}/device/poll?timeout=0`);
  assert.equal(unauthorized.status, 401);

  const health = await fetch(`${baseUrl}/healthz`).then((response) => response.json());
  assert.equal(health.service, "ghostblender-mcp");

  const initialize = await fetch(`${baseUrl}${mcpPath}`, {
    method: "POST",
    headers: {
      accept: "application/json, text/event-stream",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-03-26",
        capabilities: {},
        clientInfo: { name: "ghostblender-test", version: "0.1.0" },
      },
    }),
  });
  assert.equal(initialize.status, 200);
  const payload = await initialize.json();
  assert.equal(payload.result.serverInfo.name, "ghostblender-ipad");

  const devicePoll = fetch(`${baseUrl}/device/poll?timeout=5000`, {
    headers: {
      authorization: `Bearer ${deviceToken}`,
      "x-ghostblender-device": "Test iPad",
    },
  });
  await new Promise((resolve) => setTimeout(resolve, 10));

  const toolCall = fetch(`${baseUrl}${mcpPath}`, {
    method: "POST",
    headers: {
      accept: "application/json, text/event-stream",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: { name: "get_scene_summary", arguments: {} },
    }),
  });

  const commandResponse = await devicePoll;
  assert.equal(commandResponse.status, 200);
  const command = await commandResponse.json();
  assert.equal(command.type, "scene_summary");

  const resultResponse = await fetch(`${baseUrl}/device/result`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${deviceToken}`,
      "content-type": "application/json",
      "x-ghostblender-device": "Test iPad",
    },
    body: JSON.stringify({
      id: command.id,
      ok: true,
      result: { blenderVersion: "5.1.2", objectCount: 3 },
    }),
  });
  assert.equal(resultResponse.status, 202);

  const toolPayload = await (await toolCall).json();
  assert.equal(toolPayload.result.structuredContent.ok, true);
  assert.equal(toolPayload.result.structuredContent.result.objectCount, 3);
});
