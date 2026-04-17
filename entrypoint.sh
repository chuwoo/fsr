#!/bin/bash

set -e

CF_TEAM="vochat.teams.cloudflare.com"
FRP_SERVER="home.getput.cn"

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

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
echo "✅ FRP 服务器: ${FRP_SERVER}"

echo ""
echo "[2/6] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

echo ""
echo "[3/6] 配置 WARP..."

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

echo ""
echo "[4/6] 启动 WARP daemon..."

nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

echo "✅ WARP daemon 已启动"

echo ""
echo "[5/6] 接受服务条款并连接 WARP..."

warp-cli mode proxy || true
sleep 2
warp-cli disconnect || true
sleep 2
yes | script -q -c "warp-cli connect" /dev/null || true

sleep 10

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

echo ""
echo "[6/6] 下载 frpc 配置并启动..."
mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已下载"

    echo ""
    echo "frpc 配置："
    cat /etc/frp/frpc.toml

    frpc -c /etc/frp/frpc.toml
else
    echo "❌ 配置文件下载失败"
    tail -f /dev/null
fi
