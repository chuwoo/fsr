#!/bin/bash

set -e

CF_TEAM="vochat.teams.cloudflare.com"

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

# 检查环境变量
echo ""
echo "[1/5] 检查环境变量..."

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
echo "[2/5] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 配置 WARP
echo ""
echo "[3/5] 配置 WARP..."

# 停止现有服务
systemctl stop warp-svc 2>/dev/null || true
pkill -9 warp-svc 2>/dev/null || true

# 创建配置目录
mkdir -p /var/lib/cloudflare-warp

# 设置 MDM 配置（包含团队信息）
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

# 注册并连接
echo "注册 WARP..."
warp-cli register --accept-tos || true

echo "连接 WARP..."
warp-cli connect || true

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
echo "[4/5] 下载 frpc 配置..."
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
echo "[5/5] 启动 frpc..."

if [ -f /etc/frp/frpc.toml ]; then
    frpc -c /etc/frp/frpc.toml
else
    echo "⚠️ 无配置文件，保持运行"
    tail -f /dev/null
fi
