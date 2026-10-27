#!/data/data/com.termux/files/usr/bin/sh
# EBO Air first-time local pairing. No remote shell access or motor control.
set -eu
umask 077

DOMAIN="c3792481-1e0d-4b77-a94a-cc73b270f100-00-22liqzpphdzqb.pike.replit.dev"
BASE="https://$DOMAIN"
ROOT="$HOME/ebo-bridge"
TOKEN_FILE="$ROOT/.bridge-token"
CLIENT="$ROOT/bridge_client.mjs"
RUNNER="$ROOT/runner.sh"
BOOT="$HOME/.termux/boot/40-ebo-air-bridge"

if ! command -v pkg >/dev/null 2>&1; then
  echo "请在 Android 的 Termux 中运行此安装程序。"
  exit 2
fi
case "$DOMAIN" in
  ""|*[!A-Za-z0-9.-]*) echo "Replit domain invalid"; exit 3 ;;
esac

echo "[EBO] 初始化自动连接服务"
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  pkg update -y
  pkg install -y nodejs curl
fi

mkdir -p "$ROOT" "$HOME/.termux/boot"
chmod 700 "$ROOT"
if [ ! -f "$TOKEN_FILE" ]; then
  echo "首次配对：输入 Replit Secrets 中同一个 EBO_BRIDGE_TOKEN（输入不会显示）"
  stty -echo
  trap 'stty echo 2>/dev/null || true' EXIT INT TERM
  IFS= read -r TOKEN
  stty echo
  trap - EXIT INT TERM
  echo
  if [ "${#TOKEN}" -lt 32 ]; then
    echo "密钥长度不足。至少需要 32 个字符。"
    exit 4
  fi
  printf '%s' "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  unset TOKEN
else
  echo "[EBO] 沿用手机已保存的配对密钥"
fi

echo "[EBO] 安装/检查依赖"
if [ ! -d "$ROOT/node_modules/ws" ]; then
  (cd "$ROOT" && npm install --no-audit --no-fund --ignore-scripts ws@8.21.1)
fi

echo "[EBO] 从公开 GitHub 固定版本下载 Bridge 客户端（不包含密钥）"
curl --proto '=https' --tlsv1.2 -fLsS --connect-timeout 10 --max-time 45 \
  "https://raw.githubusercontent.com/Appsusage/Interaction-Bridge/20b331da4cb648a0e499f131c5e919c06dc6eba8/ebo-air-bridge/v1/bridge_client.mjs" -o "$CLIENT.tmp"
# HTTP 200 alone may return an HTML verification page; reject it rather than running.
if ! grep -q '^// backend/devices/ebo/android_bridge/bridge_client.mjs' "$CLIENT.tmp"; then
  echo "[EBO] 下载的不是预期 JavaScript 文件。拒绝执行。"
  rm -f "$CLIENT.tmp"
  exit 5
fi
node --check "$CLIENT.tmp" >/dev/null 2>&1 || {
  echo "[EBO] 下载客户端语法验证失败，未启动。"
  rm -f "$CLIENT.tmp"
  exit 6
}
mv "$CLIENT.tmp" "$CLIENT"
chmod 600 "$CLIENT"

cat > "$RUNNER" <<'EBO_RUNNER'
#!/data/data/com.termux/files/usr/bin/sh
set -eu
umask 077
ROOT="$HOME/ebo-bridge"
PIDFILE="$ROOT/.runner.pid"
if [ -s "$PIDFILE" ]; then
  oldpid="$(cat "$PIDFILE" 2>/dev/null || true)"
  case "$oldpid" in
    *[!0-9]*|"") ;;
    *) if kill -0 "$oldpid" 2>/dev/null; then exit 0; fi ;;
  esac
fi
printf '%s' "$$" > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT INT TERM
export EBO_BRIDGE_TOKEN="$(cat "$ROOT/.bridge-token")"
export EBO_HOST="10.63.5.246"
export EBO_PORT="46928"
export EBO_RELAY_URL="wss://__EBO_REPLIT_DOMAIN__/ebo/bridge"
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
fi
while :; do
  if [ -f "$ROOT/bridge.log" ] && [ "$(wc -c < "$ROOT/bridge.log")" -gt 262144 ]; then
    mv "$ROOT/bridge.log" "$ROOT/bridge.log.old"
  fi
  node "$ROOT/bridge_client.mjs" >> "$ROOT/bridge.log" 2>&1 || true
  sleep 4
done
EBO_RUNNER
# The heredoc is single-quoted. Substitute the authorized project domain only.
sed "s/__EBO_REPLIT_DOMAIN__/$DOMAIN/g" "$RUNNER" > "$RUNNER.tmp"
mv "$RUNNER.tmp" "$RUNNER"
chmod 700 "$RUNNER"

cat > "$BOOT" <<'EBO_BOOT'
#!/data/data/com.termux/files/usr/bin/sh
# Starts only after Termux:Boot is installed and opened once by the user.
exec "$HOME/ebo-bridge/runner.sh" > "$HOME/ebo-bridge/runner.log" 2>&1
EBO_BOOT
chmod 700 "$BOOT"

echo "[EBO] 启动 Bridge，之后自动重连"
nohup "$RUNNER" > "$ROOT/runner.log" 2>&1 < /dev/null &
sleep 2
echo "[EBO] 启动检查："
if [ -f "$ROOT/bridge.log" ]; then tail -n 10 "$ROOT/bridge.log"; else echo "日志尚未产生"; fi
echo "[EBO] 已安装自动连接守护程序。重启自动运行需要安装并打开 Termux:Boot 一次。"
echo "[EBO] 这是 Bridge 状态连接；EBO 真实运动指令尚未启用。"
echo "[EBO] 安全提醒：本脚本只建立只读连接状态通道；不授予远程命令执行权限。"
