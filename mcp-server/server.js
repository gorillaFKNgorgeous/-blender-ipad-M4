import { createServer } from "node:http";
import { randomUUID, timingSafeEqual } from "node:crypto";
import { pathToFileURL } from "node:url";

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";

const MAX_BODY_BYTES = 1024 * 1024;
const DEFAULT_COMMAND_TIMEOUT_MS = 45_000;
const DEVICE_ONLINE_WINDOW_MS = 20_000;
const MAX_QUEUE_DEPTH = 20;

function constantTimeEqual(actual, expected) {
  const actualBuffer = Buffer.from(actual ?? "", "utf8");
  const expectedBuffer = Buffer.from(expected ?? "", "utf8");
  if (actualBuffer.length !== expectedBuffer.length) return false;
  return timingSafeEqual(actualBuffer, expectedBuffer);
}

function jsonResponse(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
    "cache-control": "no-store",
  });
  res.end(body);
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

export class CommandBroker {
  constructor({ onlineWindowMs = DEVICE_ONLINE_WINDOW_MS } = {}) {
    this.onlineWindowMs = onlineWindowMs;
    this.queue = [];
    this.pollWaiters = [];
    this.pendingResults = new Map();
    this.lastSeenAt = null;
    this.device = null;
  }

  touch(device = undefined) {
    this.lastSeenAt = Date.now();
    if (device) this.device = device;
  }

  isConnected() {
    return this.lastSeenAt !== null && Date.now() - this.lastSeenAt < this.onlineWindowMs;
  }

  status() {
    return {
      connected: this.isConnected(),
      lastSeenAt: this.lastSeenAt ? new Date(this.lastSeenAt).toISOString() : null,
      device: this.device,
      queuedCommands: this.queue.length,
      pendingCommands: this.pendingResults.size,
    };
  }

  async poll(timeoutMs, device) {
    this.touch(device);
    if (this.queue.length > 0) return this.queue.shift();

    return new Promise((resolve) => {
      const waiter = { resolve, timer: null };
      waiter.timer = setTimeout(() => {
        this.pollWaiters = this.pollWaiters.filter((candidate) => candidate !== waiter);
        resolve(null);
      }, timeoutMs);
      this.pollWaiters.push(waiter);
    });
  }

  deliver(command) {
    const waiter = this.pollWaiters.shift();
    if (waiter) {
      clearTimeout(waiter.timer);
      waiter.resolve(command);
      return;
    }
    if (this.queue.length >= MAX_QUEUE_DEPTH) {
      throw new Error("The Blender command queue is full");
    }
    this.queue.push(command);
  }

  async call(type, args, timeoutMs = DEFAULT_COMMAND_TIMEOUT_MS) {
    if (!this.isConnected()) {
      throw new Error("Blender iPad is not connected. Open Blender and press Connect in GhostBlender.");
    }

    const id = randomUUID();
    const command = { id, type, args, issuedAt: new Date().toISOString() };

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingResults.delete(id);
        reject(new Error(`Blender did not answer ${type} within ${Math.round(timeoutMs / 1000)} seconds`));
      }, timeoutMs);

      this.pendingResults.set(id, { resolve, reject, timer });
      try {
        this.deliver(command);
      } catch (error) {
        clearTimeout(timer);
        this.pendingResults.delete(id);
        reject(error);
      }
    });
  }

  acceptResult(message) {
    const pending = this.pendingResults.get(message.id);
    if (!pending) return false;
    clearTimeout(pending.timer);
    this.pendingResults.delete(message.id);
    if (message.ok) pending.resolve(message.result ?? {});
    else pending.reject(new Error(message.error || "Blender command failed"));
    return true;
  }

  close() {
    for (const waiter of this.pollWaiters) {
      clearTimeout(waiter.timer);
      waiter.resolve(null);
    }
    this.pollWaiters = [];
    for (const { reject, timer } of this.pendingResults.values()) {
      clearTimeout(timer);
      reject(new Error("MCP relay is shutting down"));
    }
    this.pendingResults.clear();
  }
}

const commandOutputSchema = {
  ok: z.boolean(),
  result: z.record(z.unknown()),
};

function successResult(result, message = "Blender command completed.") {
  const normalized = result && typeof result === "object" && !Array.isArray(result)
    ? result
    : { value: result };
  return {
    content: [{ type: "text", text: message }],
    structuredContent: { ok: true, result: normalized },
  };
}

function failureResult(error) {
  return {
    isError: true,
    content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
    structuredContent: { ok: false, result: {} },
  };
}

function commandHandler(broker, type, successMessage) {
  return async (args) => {
    try {
      const result = await broker.call(type, args ?? {});
      return successResult(result, successMessage);
    } catch (error) {
      return failureResult(error);
    }
  };
}

export function createGhostBlenderMcpServer(broker) {
  const server = new McpServer(
    { name: "ghostblender-ipad", version: "0.1.0" },
    {
      instructions:
        "Controls the user's foreground Blender iPad session. Inspect status and scene before modifying it. Use only named tools; arbitrary Python is intentionally unavailable. Save only when requested. If Blender is disconnected, ask the user to open the GhostBlender panel and connect.",
    },
  );

  server.registerTool(
    "get_bridge_status",
    {
      title: "Get Blender bridge status",
      description: "Checks whether the user's Blender iPad app is currently connected to GhostBlender.",
      inputSchema: {},
      outputSchema: {
        connected: z.boolean(),
        lastSeenAt: z.string().nullable(),
        device: z.string().nullable(),
        queuedCommands: z.number(),
        pendingCommands: z.number(),
      },
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    async () => {
      const status = broker.status();
      return {
        content: [{ type: "text", text: status.connected ? "Blender iPad is connected." : "Blender iPad is disconnected." }],
        structuredContent: status,
      };
    },
  );

  server.registerTool(
    "get_scene_summary",
    {
      title: "Inspect Blender scene",
      description: "Returns the current scene, file, frame, selection and a concise object inventory from Blender on iPad.",
      inputSchema: {},
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "scene_summary", "Blender scene inspected."),
  );

  server.registerTool(
    "list_objects",
    {
      title: "List Blender objects",
      description: "Lists objects in the open Blender scene, optionally filtered by object type.",
      inputSchema: { type: z.string().max(32).optional() },
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "list_objects", "Blender objects listed."),
  );

  server.registerTool(
    "run_capability_tests",
    {
      title: "Run Blender iPad capability tests",
      description: "Runs a non-destructive test of Blender, Python, networking and writable app storage on the iPad.",
      inputSchema: {},
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: true, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "capability_tests", "Blender iPad capability tests completed."),
  );

  server.registerTool(
    "create_primitive",
    {
      title: "Create Blender primitive",
      description: "Creates one mesh primitive in the current Blender scene. Supported types: CUBE, UV_SPHERE, CYLINDER, CONE and TORUS.",
      inputSchema: {
        type: z.enum(["CUBE", "UV_SPHERE", "CYLINDER", "CONE", "TORUS"]),
        name: z.string().min(1).max(63).optional(),
        location: z.array(z.number().finite()).length(3).optional(),
        scale: z.array(z.number().finite().positive()).length(3).optional(),
      },
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "create_primitive", "Primitive created in Blender."),
  );

  server.registerTool(
    "set_object_transform",
    {
      title: "Transform Blender object",
      description: "Sets location, rotation in degrees, or scale for a named object in the open scene.",
      inputSchema: {
        name: z.string().min(1).max(63),
        location: z.array(z.number().finite()).length(3).optional(),
        rotationDegrees: z.array(z.number().finite()).length(3).optional(),
        scale: z.array(z.number().finite().positive()).length(3).optional(),
      },
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "set_object_transform", "Object transform updated in Blender."),
  );

  server.registerTool(
    "save_blend_file",
    {
      title: "Save Blender file",
      description: "Saves the open scene as a new .blend file inside Blender's iPad Documents directory. Existing files are never overwritten.",
      inputSchema: { filename: z.string().min(1).max(100) },
      outputSchema: commandOutputSchema,
      securitySchemes: [{ type: "noauth" }],
      annotations: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
    },
    commandHandler(broker, "save_blend_file", "Blender file saved."),
  );

  return server;
}

export function createGhostBlenderHttpServer(options = {}) {
  const broker = options.broker ?? new CommandBroker();
  const deviceToken = options.deviceToken ?? process.env.DEVICE_TOKEN ?? "local-device-token-change-me";
  const mcpPathToken = options.mcpPathToken ?? process.env.MCP_PATH_TOKEN ?? "local-mcp-path-change-me";
  const mcpPath = `/mcp/${mcpPathToken}`;

  if (process.env.NODE_ENV === "production") {
    if (deviceToken.length < 32 || mcpPathToken.length < 32) {
      throw new Error("DEVICE_TOKEN and MCP_PATH_TOKEN must each contain at least 32 characters in production");
    }
  }

  const httpServer = createServer(async (req, res) => {
    try {
      if (!req.url) {
        res.writeHead(400).end("Missing URL");
        return;
      }
      const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);

      if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/healthz")) {
        jsonResponse(res, 200, { service: "ghostblender-mcp", version: "0.1.0" });
        return;
      }

      if (url.pathname === "/device/poll") {
        const presented = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
        if (!constantTimeEqual(presented, deviceToken)) {
          jsonResponse(res, 401, { error: "Unauthorized device" });
          return;
        }
        if (req.method !== "GET") {
          res.writeHead(405, { allow: "GET" }).end();
          return;
        }
        const requestedTimeout = Number(url.searchParams.get("timeout") ?? 15_000);
        const timeoutMs = Math.max(0, Math.min(25_000, Number.isFinite(requestedTimeout) ? requestedTimeout : 15_000));
        const device = String(req.headers["x-ghostblender-device"] ?? "Blender iPad").slice(0, 100);
        const command = await broker.poll(timeoutMs, device);
        if (!command) {
          res.writeHead(204, { "cache-control": "no-store" }).end();
          return;
        }
        jsonResponse(res, 200, command);
        return;
      }

      if (url.pathname === "/device/result") {
        const presented = (req.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
        if (!constantTimeEqual(presented, deviceToken)) {
          jsonResponse(res, 401, { error: "Unauthorized device" });
          return;
        }
        if (req.method !== "POST") {
          res.writeHead(405, { allow: "POST" }).end();
          return;
        }
        broker.touch(String(req.headers["x-ghostblender-device"] ?? "Blender iPad").slice(0, 100));
        const message = await readJson(req);
        if (typeof message.id !== "string" || typeof message.ok !== "boolean") {
          jsonResponse(res, 400, { error: "Result requires id and ok" });
          return;
        }
        const accepted = broker.acceptResult(message);
        jsonResponse(res, accepted ? 202 : 404, { accepted });
        return;
      }

      if (req.method === "OPTIONS" && url.pathname === mcpPath) {
        res.writeHead(204, {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "POST, GET, DELETE, OPTIONS",
          "access-control-allow-headers": "content-type, mcp-session-id",
          "access-control-expose-headers": "Mcp-Session-Id",
        }).end();
        return;
      }

      const mcpMethods = new Set(["POST", "GET", "DELETE"]);
      if (url.pathname === mcpPath && req.method && mcpMethods.has(req.method)) {
        res.setHeader("access-control-allow-origin", "*");
        res.setHeader("access-control-expose-headers", "Mcp-Session-Id");
        res.setHeader("cache-control", "no-store");

        const mcpServer = createGhostBlenderMcpServer(broker);
        const transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: undefined,
          enableJsonResponse: true,
        });
        res.on("close", () => {
          transport.close();
          mcpServer.close();
        });
        await mcpServer.connect(transport);
        await transport.handleRequest(req, res);
        return;
      }

      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end("Not Found");
    } catch (error) {
      console.error("Request failed", error);
      if (!res.headersSent) jsonResponse(res, 500, { error: "Internal server error" });
      else res.end();
    }
  });

  httpServer.on("close", () => broker.close());
  return { httpServer, broker, mcpPath };
}

export function startServer(options = {}) {
  const port = Number(options.port ?? process.env.PORT ?? 8080);
  const instance = createGhostBlenderHttpServer(options);
  instance.httpServer.listen(port, () => {
    console.log(`GhostBlender MCP listening on port ${port}; MCP path is configured`);
  });
  return instance;
}

const invokedDirectly = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (invokedDirectly) startServer();
