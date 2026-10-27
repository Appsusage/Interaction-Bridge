#!/data/data/com.termux/files/usr/bin/sh
# Original EBO AIR: isolated read-only Android diagnostics via Cloudflare Quick Tunnel.
# No Replit Publish, no root, no remote shell access and no motor commands.
set -eu
umask 077
ROOT="$HOME/ebo-bridge"
SERVER="$ROOT/tunnel_status_server.mjs"
TEMP="$ROOT/tunnel_status_server.next.mjs"
PINNED="https://raw.githubusercontent.com/Appsusage/Interaction-Bridge/b5828f757bc6aaa544b671b0b8a7096d4b00d401/ebo-air-bridge/v3/tunnel_status_server.mjs"

if [ ! -s "$ROOT/.bridge-token" ]; then
  echo "[EBO] 未找到之前保存的配对密钥；先完成 EBO Bridge 首次配对。"
  exit 2
fi
if ! command -v node >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "[EBO] Termux 的 Node.js 或 curl 尚未恢复。"
  exit 3
fi
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "[EBO] 安装 Termux 官方 cloudflared 软件包"
  pkg install cloudflared -y
fi

echo "[EBO] 下载仅提供状态的手机本地 Bridge 服务"
curl --proto '=https' --tlsv1.2 -fsSL --max-time 30 "$PINNED" -o "$TEMP"
if ! head -n 1 "$TEMP" | grep -Fqx '// EBO AIR v1 / Android Termux: password-protected, read-only diagnostics.'; then
  echo "[EBO] 下载内容异常，已拒绝执行"
  rm -f "$TEMP"
  exit 4
fi
node --check "$TEMP"
mv "$TEMP" "$SERVER"
chmod 600 "$SERVER"

# Safe to rerun: do not start a second server if one is already serving port 8765.
status="$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/status || true)"
if [ "$status" != "401" ]; then
  echo "[EBO] 开启仅监听 127.0.0.1:8765 的认证服务"
  nohup node "$SERVER" > "$ROOT/tunnel-server.log" 2>&1 </dev/null &
  sleep 2
  status="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8765/status || true)"
fi
if [ "$status" != "401" ]; then
  echo "[EBO] 本地认证端点未启动（预期未授权请求返回 401）"
  tail -n 12 "$ROOT/tunnel-server.log" 2>/dev/null || true
  exit 5
fi
echo "[EBO] 手机本地认证服务已启动，未授权请求被拒绝。"
echo "[EBO] 正在向 Cloudflare 创建临时隧道..."
echo "[EBO] 请将随后出现的 https://...trycloudflare.com 地址复制给 ChatGPT。"
echo "[EBO] 不要分享 EBO_BRIDGE_TOKEN 或其他令牌。"
exec cloudflared tunnel --url http://127.0.0.1:8765
