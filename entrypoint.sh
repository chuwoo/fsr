#!/bin/bash

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

# 环境变量检查
if [ -z "$CF_ID" ] || [ -z "$CF_TOKEN" ]; then
    echo "❌ 请设置 CF_ID 和 CF_TOKEN"
    echo "容器保持运行，可以 exec 进来调试"
    tail -f /dev/null
fi

echo "✅ 团队: ${CF_TEAM}"

# 清理旧进程
echo "[1/3] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 配置 WARP MDM
echo "[2/3] 配置 WARP (Teams)..."
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

# 启动 warp-svc
echo "[3/3] 启动 WARP..."
nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

# 注册
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    echo "正在注册设备..."
    warp-cli register || true
    sleep 2
fi

# 尝试 proxy 模式
echo ""
echo "=== 尝试 proxy 模式 ==="
warp-cli mode proxy || true
warp-cli disconnect 2>/dev/null || true
sleep 2
yes | script -q -c "warp-cli connect" /dev/null || true
sleep 10

echo ""
echo "proxy 模式状态："
warp-cli status
echo -n "IPv4: "; curl -s -4 ifconfig.me || echo "失败"
echo ""
echo -n "IPv6: "; curl -s -6 ifconfig.me || echo "无"
warp-cli disconnect 2>/dev/null || true
sleep 2

# 尝试 warp 全隧道模式
echo ""
echo "=== 尝试 warp 全隧道模式 ==="
warp-cli mode warp || true
sleep 2
yes | script -q -c "warp-cli connect" /dev/null || true

echo "等待连接（最多30秒）..."
for i in {1..15}; do
    STATUS=$(warp-cli status 2>/dev/null | grep -oP 'Status: \K\w+' || echo "Unknown")
    echo "  第${i}次: $STATUS"
    if [ "$STATUS" = "Connected" ]; then
        echo "✅ WARP 全隧道已连接"
        break
    fi
    sleep 2
done

echo ""
echo "warp 全隧道模式状态："
warp-cli status
echo -n "IPv4: "; curl -s -4 ifconfig.me || echo "失败"
echo ""
echo -n "IPv6: "; curl -s -6 ifconfig.me || echo "无"
echo ""
echo "网卡信息："
ip addr show 2>/dev/null || ifconfig
echo ""
echo "IPv6 路由："
ip -6 route show 2>/dev/null || echo "无"
echo ""
echo "=== 全部完成，容器保持运行 ==="
echo "可以 docker exec -it 进来查看"

tail -f /dev/null
