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

# 等待 warp-svc 就绪（最多 10 秒）
for i in $(seq 1 20); do
    warp-cli status >/dev/null 2>&1 && break
    sleep 0.5
done
warp-cli status >/dev/null 2>&1 || { echo "❌ warp-svc 启动超时"; exit 1; }
echo "   ✅ warp-svc 就绪"

# ---- 注册 WARP（Service Token）----
echo "[2/6] 用 Service Token 注册 (${TEAM_NAME})..."
# 尝试不同版本的 warp-cli 注册语法
warp-cli teams-enroll "${TEAM_NAME}" <<< "$(printf '%s\n%s\n' "${CF_ID}" "${CF_TOKEN}")" 2>&1 || \
warp-cli teams-enroll "${TEAM_NAME}" "${CF_ID}" "${CF_TOKEN}" 2>&1 || \
warp-cli registration new "${CF_ID}" "${CF_TOKEN}" 2>&1 || true

# 验证注册
STATUS=$(warp-cli status 2>&1 || true)
echo "   $STATUS"

# ---- 设置隧道模式 ----
echo "[3/6] 配置隧道模式..."
warp-cli set-mode warp 2>&1 || true

# 启动 WARP 连接
echo "[4/6] 连接 WARP..."
warp-cli connect 2>&1 || true

# 等待连接建立（最多 30 秒）
for i in $(seq 1 30); do
    STATUS=$(warp-cli status 2>&1 || true)
    echo "$STATUS" | grep -qi "connected" && break
    sleep 1
done

echo "   WARP 状态: $(warp-cli status 2>&1 || echo 'unknown')"

# ---- 验证网络 ----
echo "[5/6] 验证网络..."
ping6 -c1 -W5 2606:4700:4700::1111 >/dev/null 2>&1 \
    && echo "   ✅ IPv6 可达" \
    || echo "   ⚠️ IPv6 暂不可达（可能需要几秒）"

# ---- 下载 frpc 配置 ----
echo "[6/6] 下载 frpc 配置..."
mkdir -p /etc/frp
FRPC_URL="${FRP_REPO}/${FRP_CON}"
echo "   URL: $FRPC_URL"
curl -fsSL -o "$FRPC_CONF" "$FRPC_URL" || { echo "❌ 下载失败"; exit 1; }
echo "   ✅ frpc 配置就绪"

# ---- 启动 frpc ----
echo ""
echo "=============================="
echo "  启动 frpc（通过 WARP 隧道）"
echo "=============================="
exec frpc -c "$FRPC_CONF"
