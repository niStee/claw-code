#!/usr/bin/env node
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const listenPort = Number.parseInt(process.argv[2] || "8099", 10);
const targetBase = new URL(process.argv[3] || "http://127.0.0.1:8098");
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..");
const logDir = process.argv[4] ? path.resolve(process.argv[4]) : path.join(repoRoot, "logs");
const logPath = path.join(logDir, "claw-routes.ndjson");
const latestPath = path.join(logDir, "claw-routes.latest.json");
const maxLogBytes = Number.parseInt(process.env.CLAW_ROUTE_TAP_MAX_LOG_BYTES || `${10 * 1024 * 1024}`, 10);
const maxRotatedLogs = Number.parseInt(process.env.CLAW_ROUTE_TAP_MAX_ROTATED || "5", 10);
const breakerMode = (process.env.CLAW_ROUTE_TAP_CIRCUIT_BREAKER || "log").toLowerCase();
const breakerThreshold = Number.parseInt(process.env.CLAW_ROUTE_TAP_BREAKER_THRESHOLD || "5", 10);
const breakerSeconds = Number.parseInt(process.env.CLAW_ROUTE_TAP_BREAKER_SECONDS || "300", 10);
const breakerState = new Map();

fs.mkdirSync(logDir, { recursive: true });

function headerValue(headers, name) {
  const value = headers[name.toLowerCase()];
  if (Array.isArray(value)) {
    return value.join(", ");
  }
  return value ? String(value) : "";
}

function providerFromApiBase(apiBase) {
  if (apiBase.includes("generativelanguage.googleapis.com")) return "AI Studio API key";
  if (apiBase.includes("aiplatform.googleapis.com") && apiBase.includes("/gemini-")) return "Google Cloud / Vertex credits";
  if (apiBase.includes("aiplatform.googleapis.com") && apiBase.includes("/claude-")) return "Google Cloud / Vertex Claude";
  if (apiBase.includes(":8089/")) return "Codex proxy / ChatGPT subscription";
  if (apiBase.includes(":4000/")) return "VS Code LM / Copilot";
  if (apiBase.includes(":4999/")) return "Antigravity direct-only";
  if (apiBase.includes("deepseek.com")) return "DeepSeek paid overflow";
  return apiBase ? "custom/unknown" : "unknown";
}

function parseRequestSummary(body) {
  try {
    const json = JSON.parse(body.toString("utf8"));
    return {
      requested_model: typeof json.model === "string" ? json.model : "",
      stream: Boolean(json.stream),
    };
  } catch {
    return { requested_model: "", stream: false };
  }
}

function extractResponseModel(text) {
  const match = text.match(/"model"\s*:\s*"([^"]+)"/);
  return match ? match[1] : "";
}

function rotateTraceLogIfNeeded() {
  if (!Number.isFinite(maxLogBytes) || maxLogBytes <= 0 || !fs.existsSync(logPath)) {
    return;
  }

  const size = fs.statSync(logPath).size;
  if (size < maxLogBytes) {
    return;
  }

  for (let i = maxRotatedLogs; i >= 1; i -= 1) {
    const source = i === 1 ? logPath : `${logPath}.${i - 1}`;
    const target = `${logPath}.${i}`;
    if (!fs.existsSync(source)) {
      continue;
    }
    if (i === maxRotatedLogs && fs.existsSync(target)) {
      fs.rmSync(target, { force: true });
    }
    fs.renameSync(source, target);
  }
}

function getBreakerKey(traceOrSummary) {
  return traceOrSummary.requested_model || "unknown";
}

function isCircuitOpen(summary) {
  if (breakerMode !== "block") {
    return false;
  }
  const state = breakerState.get(getBreakerKey(summary));
  return Boolean(state && state.openUntil && Date.now() < state.openUntil);
}

function updateCircuitBreaker(trace) {
  if (trace.path !== "/v1/chat/completions") {
    return;
  }

  const key = getBreakerKey(trace);
  const state = breakerState.get(key) || { consecutive429: 0, openUntil: 0 };
  if (trace.status === 429) {
    state.consecutive429 += 1;
    if (state.consecutive429 >= breakerThreshold) {
      state.openUntil = Date.now() + breakerSeconds * 1000;
      console.log(`[route-tap] 429 breaker ${breakerMode}: ${key} has ${state.consecutive429} consecutive 429s; open for ${breakerSeconds}s`);
    }
  } else if (trace.status > 0 && trace.status < 400) {
    state.consecutive429 = 0;
    state.openUntil = 0;
  }
  breakerState.set(key, state);
}

function appendTrace(trace) {
  rotateTraceLogIfNeeded();
  updateCircuitBreaker(trace);
  const line = JSON.stringify(trace);
  fs.appendFile(logPath, `${line}\n`, () => {});
  fs.writeFile(latestPath, `${JSON.stringify(trace, null, 2)}\n`, () => {});

  const selected = trace.response_model || trace.selected_model_id || trace.model_group || "unknown";
  const fallbackText = trace.fallbacks_attempted ? ` fallbacks=${trace.fallbacks_attempted}` : "";
  console.log(`[route] ${trace.status} ${trace.requested_model || "-"} -> ${selected} (${trace.provider})${fallbackText}`);
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

const server = http.createServer(async (clientReq, clientRes) => {
  const started = Date.now();
  let body;
  try {
    body = await collectBody(clientReq);
  } catch (error) {
    clientRes.writeHead(400, { "content-type": "application/json" });
    clientRes.end(JSON.stringify({ error: { message: `Could not read request body: ${error.message}` } }));
    return;
  }

  const summary = parseRequestSummary(body);
  if (isCircuitOpen(summary)) {
    const trace = {
      ts: new Date().toISOString(),
      method: clientReq.method,
      path: new URL(clientReq.url || "/", targetBase).pathname,
      status: 503,
      requested_model: summary.requested_model,
      stream: summary.stream,
      provider: "route tap circuit breaker",
      error: "consecutive 429 circuit breaker open",
      proxy_duration_ms: Date.now() - started,
    };
    appendTrace(trace);
    clientRes.writeHead(503, { "content-type": "application/json", "retry-after": String(breakerSeconds) });
    clientRes.end(JSON.stringify({ error: { message: `Route tap circuit breaker is open for model '${summary.requested_model}'. Retry later or switch provider lane.` } }));
    return;
  }

  const target = new URL(clientReq.url || "/", targetBase);
  const requestHeaders = { ...clientReq.headers, host: target.host };
  requestHeaders["content-length"] = Buffer.byteLength(body);

  const upstreamReq = http.request(
    {
      protocol: target.protocol,
      hostname: target.hostname,
      port: target.port,
      path: `${target.pathname}${target.search}`,
      method: clientReq.method,
      headers: requestHeaders,
    },
    (upstreamRes) => {
      clientRes.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);

      const apiBase = headerValue(upstreamRes.headers, "x-litellm-model-api-base");
      const trace = {
        ts: new Date().toISOString(),
        method: clientReq.method,
        path: target.pathname,
        status: upstreamRes.statusCode || 0,
        requested_model: summary.requested_model,
        stream: summary.stream,
        model_group: headerValue(upstreamRes.headers, "x-litellm-model-group"),
        selected_model_id: headerValue(upstreamRes.headers, "x-litellm-model-id"),
        api_base: apiBase,
        provider: providerFromApiBase(apiBase),
        fallbacks_attempted: headerValue(upstreamRes.headers, "x-litellm-attempted-fallbacks"),
        retries_attempted: headerValue(upstreamRes.headers, "x-litellm-attempted-retries"),
        call_id: headerValue(upstreamRes.headers, "x-litellm-call-id"),
        response_cost: headerValue(upstreamRes.headers, "x-litellm-response-cost-original") ||
          headerValue(upstreamRes.headers, "x-litellm-response-cost"),
        response_duration_ms: headerValue(upstreamRes.headers, "x-litellm-response-duration-ms"),
        proxy_duration_ms: Date.now() - started,
      };

      let responseModel = "";
      let inspectBuffer = "";
      upstreamRes.on("data", (chunk) => {
        if (!responseModel && target.pathname === "/v1/chat/completions") {
          inspectBuffer = `${inspectBuffer}${chunk.toString("utf8")}`.slice(0, 16384);
          responseModel = extractResponseModel(inspectBuffer);
        }
        clientRes.write(chunk);
      });
      upstreamRes.on("end", () => {
        trace.response_model = responseModel;
        trace.proxy_duration_ms = Date.now() - started;
        appendTrace(trace);
        clientRes.end();
      });
    },
  );

  upstreamReq.on("error", (error) => {
    const trace = {
      ts: new Date().toISOString(),
      method: clientReq.method,
      path: target.pathname,
      status: 502,
      requested_model: summary.requested_model,
      stream: summary.stream,
      provider: "route tap error",
      error: error.message,
      proxy_duration_ms: Date.now() - started,
    };
    appendTrace(trace);
    clientRes.writeHead(502, { "content-type": "application/json" });
    clientRes.end(JSON.stringify({ error: { message: `Route tap upstream error: ${error.message}` } }));
  });

  upstreamReq.end(body);
});

server.listen(listenPort, "127.0.0.1", () => {
  console.log(`[route-tap] listening on http://127.0.0.1:${listenPort}`);
  console.log(`[route-tap] forwarding to ${targetBase.origin}`);
  console.log(`[route-tap] writing ${logPath}`);
});
