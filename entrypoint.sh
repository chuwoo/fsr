#!/bin/bash
set -euo pipefail

FRPC_CONF="/etc/frp/frpc.toml"
TEAM_NAME="vochat"

echo "=============================="
echo "  WARP + frpc 容器启动"
echo "=============================="

# ---- 检查环境变量 ----
MISSING=0
for VAR in CF_ID CF_TOKEN FRP_CON FRP_REPO; do
    if [ -z "${!VAR:-}" ]; then
        echo "❌ 缺少环境变量: $VAR"
        MISSING=1
    fi
done
[ $MISSING -eq 1 ] && exit 1

echo "   团队名: ${TEAM_NAME}"
echo "   FRPC 配置: ${FRP_CON}"

# ---- 启动 warp-svc ----
echo "[1/6] 启动 warp-svc..."
warp-svc &
WARP_PID=$!
trap "kill $WARP_PID 2>/dev/null || true" EXIT

# 等待 warp-svc IPC 就绪（用 warp-cli 能连上就行，不管注册状态）
for i in $(seq 1 20); do
    warp-cli status 2>&1 | grep -q "." && break
    sleep 0.5
done
echo "   ✅ warp-svc 就绪"

# ---- 注册 WARP ----
echo "[2/6] 注册 WARP..."

# 先注册为普通用户
warp-cli --accept-tos registration new 2>&1
sleep 1

# 尝试 Zero Trust 团队注册
echo "   尝试加入团队 ${TEAM_NAME}..."
TEAM_OK=0
echo "$CF_TOKEN" | warp-cli teams-enroll "$TEAM_NAME" 2>&1 && TEAM_OK=1
if [ $TEAM_OK -eq 0 ]; then
    warp-cli teams-enroll "$TEAM_NAME" "$CF_TOKEN" 2>&1 && TEAM_OK=1 || true
fi

if [ $TEAM_OK -eq 1 ]; then
    echo "   ✅ 团队注册成功"
else
    echo "   ⚠️ 团队注册失败，使用普通 WARP 模式"
fi

echo "   注册状态: $(warp-cli registration show 2>&1 || echo 'unknown')"

# ---- 设置代理模式 ----
echo "[3/6] 配置代理模式 (SOCKS5:40000)..."
warp-cli set-mode proxy 2>&1
warp-cli proxy port 40000 2>&1

# ---- 连接 WARP ----
echo "[4/6] 连接 WARP..."
warp-cli connect 2>&1

# 等待连接（最多 30 秒）
CONNECTED=0
for i in $(seq 1 30); do
    if warp-cli status 2>&1 | grep -qi "connected"; then
        echo "   ✅ WARP 已连接"
        CONNECTED=1
        break
    fi
    sleep 1
done
[ $CONNECTED -eq 0 ] && echo "   ⚠️ WARP 连接超时，继续尝试..."

echo "   WARP 状态: $(warp-cli status 2>&1 || echo 'unknown')"

# ---- 验证网络 ----
echo "[5/6] 验证网络..."
IPV6=$(curl -6 -s --max-time 5 https://api64.ipify.org 2>/dev/null || echo "不可达")
echo "   IPv6 出口: $IPV6"

# ---- 下载 frpc 配置 ----
echo "[6/6] 下载 frpc 配置..."
mkdir -p /etc/frp
FRPC_URL="${FRP_REPO}/${FRP_CON}"
echo "   URL: $FRPC_URL"
curl -fsSL -o "$FRPC_CONF" "$FRPC_URL" || { echo "❌ 下载失败: $FRPC_URL"; exit 1; }
echo "   ✅ frpc 配置就绪"

# ---- 启动 frpc ----
echo ""
echo "=============================="
echo "  启动 frpc"
echo "=============================="
exec frpc -c "$FRPC_CONF"
