#!/bin/bash

set -e

CF_TEAM="vochat.teams.cloudflare.com"
FRP_SERVER="home.getput.cloudns.org"

echo "=========================================="
echo "  WARP + socat + frpc (vochat)"
echo "=========================================="

echo ""
echo "[1/7] 检查环境变量..."

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
echo "[2/7] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
pkill -f socat 2>/dev/null || true
sleep 2

echo ""
echo "[3/7] 配置 WARP..."

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
echo "[4/7] 启动 WARP daemon..."

nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

echo "✅ WARP daemon 已启动"

echo ""
echo "[5/7] 接受服务条款并连接 WARP..."

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
echo "[6/7] 启动 socat 代理..."

# socat 转发 TCP 连接到 WARP SOCKS5 代理
nohup socat TCP-LISTEN:6500,fork SOCKS:127.0.0.1:${FRP_SERVER}:6500,socksport=1080 > /var/log/socat.log 2>&1 &
SOCAT_PID=$!

sleep 3

if ps -p $SOCAT_PID > /dev/null 2>&1; then
    echo "✅ socat 已启动 (PID: $SOCAT_PID)"
    echo "✅ 转发: localhost:6500 -> ${FRP_SERVER}:6500 (via WARP SOCKS5)"
else
    echo "❌ socat 启动失败"
    cat /var/log/socat.log
fi

echo ""
echo "[7/7] 下载 frpc 配置并启动..."
mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已下载"
    
    # 修改 serverAddr 为本地
    sed -i 's/serverAddr = "home.getput.cn"/serverAddr = "127.0.0.1"/' /etc/frp/frpc.toml
    
    echo ""
    echo "frpc 配置："
    cat /etc/frp/frpc.toml
    
    frpc -c /etc/frp/frpc.toml
else
    echo "❌ 配置文件下载失败"
    tail -f /dev/null
fi
