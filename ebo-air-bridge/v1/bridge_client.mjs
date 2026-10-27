// backend/devices/ebo/android_bridge/bridge_client.mjs
// Run in Termux on a phone that can reach the original EBO Air LAN.
// Read-only connectivity diagnostics; never sends a motor packet.
import { WebSocket } from "ws";
import dgram from "node:dgram";
import { execFile } from "node:child_process";
import { isIP } from "node:net";

const endpoint = process.env.EBO_RELAY_URL || "";
const token = process.env.EBO_BRIDGE_TOKEN || "";
const host = process.env.EBO_HOST || "10.63.5.246";
const port = Number(process.env.EBO_PORT || 46928);
if (!endpoint || token.length < 32 || isIP(host) !== 4 ||
    !Number.isInteger(port) || port < 1 || port > 65535) {
  throw new Error("Set EBO_RELAY_URL, EBO_BRIDGE_TOKEN (>=32 chars), and valid EBO_HOST/EBO_PORT.");
}
const url = new URL(endpoint);
if (url.protocol !== "wss:" && !(url.protocol === "ws:" &&
  ["localhost", "127.0.0.1"].includes(url.hostname))) {
  throw new Error("Bridge transport must use encrypted wss:// (ws:// only for localhost tests).");
}
if (url.pathname !== "/ebo/bridge") throw new Error("Expected /ebo/bridge endpoint.");

let stopped = false;
let ws = null;
let udpReady = false;
let attempt = 0;
let reporting = null;
let retryTimer = null;
const udp = dgram.createSocket("udp4");
udp.on("error", error => {
  udpReady = false;
  console.error("[EBO] UDP socket error:", error.message);
});
udp.bind(0, "0.0.0.0", () => {
  udpReady = true;
  console.log("[EBO] UDP socket ready (robot handshake NOT verified)");
});
// No unsolicited device commands / packets are sent.

function checkLan() {
  return new Promise(resolve => {
    execFile("ping", ["-c", "1", "-W", "2", host], { timeout: 4000 }, (error) => {
      if (error?.code === "ENOENT") return resolve({ lanReachable: null, lanCheck: "ping_unavailable" });
      if (error) return resolve({ lanReachable: false, lanCheck: "ping_failed" });
      resolve({ lanReachable: true, lanCheck: "ping_ok" });
    });
  });
}

async function report() {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  const result = await checkLan();
  if (ws?.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify({ type: "status", udpSocketReady: udpReady, ...result }));
  console.log("[EBO] Relay online; LAN:", result.lanCheck, "; robot auth: pending");
}

function reconnect() {
  if (stopped) return;
  const delay = Math.min(30000, 1000 * (2 ** Math.min(attempt++, 5)));
  retryTimer = setTimeout(connect, delay);
}

function connect() {
  if (stopped) return;
  console.log("[EBO] Opening secure outbound bridge");
  ws = new WebSocket(url.toString(), { handshakeTimeout: 10000, maxPayload: 4096 });
  let authenticated = false;
  ws.on("open", () => {
    ws.send(JSON.stringify({ type: "auth", token }));
  });
  ws.on("message", raw => {
    let msg;
    try { msg = JSON.parse(raw.toString("utf8")); } catch { return; }
    if (msg.type === "auth_ok" && !authenticated) {
      authenticated = true;
      attempt = 0;
      console.log("[EBO] Replit authenticated, read-only mode");
      report().catch(error => console.error(error.message));
      reporting = setInterval(() => report().catch(error => console.error(error.message)), 15000);
    }
  });
  ws.on("error", error => console.error("[EBO] Bridge:", error.message));
  ws.on("close", () => {
    if (reporting) clearInterval(reporting);
    reporting = null;
    if (!stopped) reconnect();
  });
}

function shutdown() {
  stopped = true;
  clearTimeout(retryTimer);
  clearInterval(reporting);
  ws?.close();
  udp.close();
}
process.once("SIGINT", shutdown);
process.once("SIGTERM", shutdown);
connect();
