#!/data/data/com.termux/files/usr/bin/sh
# Local one-time Replit Shield pairing; no remote shell or robot motor actions.
set -eu
umask 077
ROOT="$HOME/ebo-bridge"
CLIENT="$ROOT/bridge_client.mjs"
ACCESS="$ROOT/.replit-access-token"
NEXT="$ROOT/bridge_client.next.mjs"
URL="https://raw.githubusercontent.com/Appsusage/Interaction-Bridge/a2dbe6c2572e0c8c697ae650383228d1d898dfae/ebo-air-bridge/v2/bridge_client.mjs"
if [ ! -f "$ROOT/.bridge-token" ]; then
  echo "[EBO] 原有 Bridge 尚未配对，请先完成初次安装。"
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  echo "[EBO] node 不可用，请先修复 Termux。"
  exit 3
fi
echo "[EBO] 下载升级后的 Bridge 客户端（不含任何密钥）"
node --input-type=module - "$URL" "$NEXT" <<'EBO_FETCH'
import fs from "node:fs";
const [url, destination] = process.argv.slice(2);
const response = await fetch(url, { signal: AbortSignal.timeout(25000) });
if (!response.ok) throw Error("Download HTTP " + response.status);
const content = await response.text();
if (!content.startsWith("// backend/devices/ebo/android_bridge/bridge_client.mjs") ||
    !content.includes("getReplitAccessToken")) {
  throw Error("Downloaded content is not the expected Bridge v2 client");
}
fs.writeFileSync(destination, content, { mode: 0o600 });
EBO_FETCH
node --check "$NEXT"
mv "$NEXT" "$CLIENT"
chmod 600 "$CLIENT"
echo "[EBO] 请在 Replit 创建 External Access Token，Environment 选 Development。"
echo "[EBO] 输入该令牌（不是 EBO_BRIDGE_TOKEN），输入时不会显示："
stty -echo
trap 'stty echo 2>/dev/null || true' EXIT INT TERM
IFS= read -r TOKEN
stty echo
trap - EXIT INT TERM
echo
if [ "${#TOKEN}" -lt 16 ]; then
  echo "[EBO] 访问令牌长度不符合预期，已停止。"
  exit 4
fi
printf '%s' "$TOKEN" > "$ACCESS.next"
chmod 600 "$ACCESS.next"
mv "$ACCESS.next" "$ACCESS"
unset TOKEN
echo "[EBO] 已保存到手机私有目录，仅本机 Bridge 读取。"
node --input-type=module - "$CLIENT" <<'EBO_RESTART'
import fs from "node:fs";
const client = process.argv[2];
let count = 0;
for (const entry of fs.readdirSync("/proc")) {
  if (!/^\d+$/.test(entry) || Number(entry) === process.pid) continue;
  try {
    const args = fs.readFileSync("/proc/" + entry + "/cmdline", "utf8").split("\0").filter(Boolean);
    const exe = args[0] || "";
    if (!/\/node(?:js)?$/.test(exe) || !args.includes(client)) continue;
    process.kill(Number(entry), "SIGTERM");
    count++;
  } catch {}
}
console.log("[EBO] 已通知 " + count + " 个现有 Bridge 进程重新启动。");
EBO_RESTART
echo "[EBO] 使用原有自动重连守护进程继续运行。"
echo "[EBO] 稍后可用 tail -n 20 ~/ebo-bridge/bridge.log 查看握手结果。"
