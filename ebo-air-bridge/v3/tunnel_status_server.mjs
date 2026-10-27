// EBO AIR v1 / Android Termux: password-protected, read-only diagnostics.
// Expose ONLY through a user-started Cloudflare Tunnel.
// No shell commands, movement commands, camera streams or UDP control packets.
import http from "node:http";
import { readFileSync } from "node:fs";
import { timingSafeEqual } from "node:crypto";
import { execFile } from "node:child_process";

const HOST = "127.0.0.1";
const PORT = Number(process.env.EBO_LOCAL_PORT || 8765);
const DEVICE_IP = process.env.EBO_HOST || "10.63.5.246";
const TOKEN_PATH = process.env.EBO_TOKEN_FILE || process.env.HOME + "/ebo-bridge/.bridge-token";

if (!Number.isInteger(PORT) || PORT < 1024 || PORT > 65535) throw new Error("Invalid local port");
if (!/^10\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(DEVICE_IP)) throw new Error("Invalid device LAN IP");
const secret = readFileSync(TOKEN_PATH, "utf8").trim();
if (secret.length < 32) throw new Error("EBO local secret is missing or too short");
const secretBuffer = Buffer.from(secret, "utf8");

function validToken(auth) {
  if (typeof auth !== "string" || !auth.startsWith("Bearer ") || auth.length > 4096) return false;
  const candidate = Buffer.from(auth.slice(7), "utf8");
  return candidate.length === secretBuffer.length && timingSafeEqual(candidate, secretBuffer);
}

function probeLan() {
  return new Promise(resolve => {
    execFile("ping", ["-c", "1", "-W", "2", DEVICE_IP], { timeout: 3500 }, error => {
      resolve(error ? (error.code === "ENOENT" ? "ping_unavailable" : "ping_failed") : "ping_ok");
    });
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  if (req.url !== "/status" || req.method !== "GET") {
    res.writeHead(404).end();
    return;
  }
  if (!validToken(req.headers.authorization)) {
    res.writeHead(401, { "WWW-Authenticate": 'Bearer realm="ebo-air"' }).end();
    return;
  }
  const lanCheck = await probeLan();
  res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify({
    type: "ebo_air_readonly_status",
    bridgeOnline: true,
    deviceIp: DEVICE_IP,
    lanCheck,
    lanReachable: lanCheck === "ping_ok" ? true : lanCheck === "ping_failed" ? false : null,
    robotAuthenticated: false,
    motorCommandsEnabled: false,
    checkedAt: new Date().toISOString()
  }));
});

server.requestTimeout = 6000;
server.headersTimeout = 8000;
server.listen(PORT, HOST, () => console.log("[EBO] Read-only local bridge on http://" + HOST + ":" + PORT));
process.on("SIGINT", () => server.close());
process.on("SIGTERM", () => server.close());
