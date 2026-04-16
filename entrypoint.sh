#!/bin/bash

set -e

CF_TEAM="vochat.teams.cloudflare.com"

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

# 检查环境变量
echo ""
echo "[1/6] 检查环境变量..."

if [ -z "$CF_ID" ]; then
    echo "❌ 请设置 CF_ID"
    exit 1
fi

if [ -z "$CF_TOKEN" ]; then
    echo "❌ 请设置 CF_TOKEN"
    exit 1
fi

echo "✅ 团队: ${CF_TEAM}"
echo "✅ Client ID: ${CF_ID}"

# 清理旧进程
echo ""
echo "[2/6] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 启动 WARP daemon
echo ""
echo "[3/6] 启动 WARP daemon..."

nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

echo "✅ WARP daemon 已启动"

# 配置 WARP
echo ""
echo "[4/6] 配置 WARP..."

# 设置 MDM 配置
mkdir -p /var/lib/cloudflare-warp
cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<dict>
    <key>organization</key>
    <string>${CF_TEAM}</string>
    <key>auth_client_id</key>
    <string>${CF_ID}</string>
    <key>auth_client_secret</key>
    <string>${CF_TOKEN}</string>
</dict>
EOF

# 接受条款（尝试环境变量方式）
export WARP_ACCEPT_TOS=true
echo "WARP_ACCEPT_TOS=true"

# 尝试用 script 模拟 TTY
echo "连接 WARP..."
script -q -c "warp-cli connect" /dev/null || warp-cli connect || true

sleep 10

# 检查状态
echo ""
echo "WARP 状态："
warp-cli status

echo ""
echo "出口 IP："
echo -n "IPv4: "
curl -s -4 ifconfig.me
echo ""
echo -n "IPv6: "
curl -s -6 ifconfig.me || echo "无"

# 下载 frpc 配置
echo ""
echo "[5/6] 下载 frpc 配置..."
mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已下载"
else
    echo "⚠️ 无配置文件"
fi

# 启动 frpc
echo ""
echo "[6/6] 启动 frpc..."

if [ -f /etc/frp/frpc.toml ]; then
    frpc -c /etc/frp/frpc.toml
else
    echo "⚠️ 无配置文件，保持运行"
    tail -f /dev/null
fi
