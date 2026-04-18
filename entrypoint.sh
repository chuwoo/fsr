#!/bin/bash
set -e

echo "=========================================="
echo "  WARP + frpc"
echo "=========================================="

# 检查环境变量
if [ -z "$WARP_TOKEN" ]; then
    echo "❌ 请设置 WARP_TOKEN"
    tail -f /dev/null
fi

echo "✅ WARP_TOKEN 已设置"

# 清理旧进程
echo "[1/5] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 配置 WARP MDM
echo "[2/5] 配置 WARP MDM..."
mkdir -p /var/lib/cloudflare-warp
cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<dict>
    <key>organization</key>
    <string>vochat.teams.cloudflare.com</string>
</dict>
EOF

# 启动 WARP
echo "[3/5] 启动 WARP daemon..."
nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

# 注册 WARP
echo "[4/5] 注册 WARP..."
rm -f /var/lib/cloudflare-warp/reg.json
warp-cli --accept-tos teams-enroll-token "${WARP_TOKEN}"

# 连接
echo "连接 WARP..."
warp-cli connect || true
sleep 10

# 检查状态
echo ""
echo "WARP 状态："
warp-cli status

echo ""
echo "出口 IP："
echo -n "IPv4: "; curl -s -4 ifconfig.me || echo "失败"
echo -n "IPv6: "; curl -s -6 ifconfig.me || echo "无"

# 下载 frpc 配置
echo ""
echo "[5/5] 下载 frpc 配置..."
mkdir -p /etc/frp
if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已下载"
    frpc -c /etc/frp/frpc.toml
else
    echo "⚠️ 无配置文件，保持运行"
    tail -f /dev/null
fi
