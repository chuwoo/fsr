#!/bin/bash

echo "=========================================="
echo "  WARP 调试脚本"
echo "=========================================="

# 环境变量
if [ -z "$CF_ID" ]; then
    echo "❌ CF_ID 未设置"
else
    echo "✅ CF_ID: ${CF_ID}"
fi

if [ -z "$CF_TOKEN" ]; then
    echo "❌ CF_TOKEN 未设置"
else
    echo "✅ CF_TOKEN: 已设置"
fi

echo ""
echo "=========================================="
echo "1. 清理旧进程..."
echo "=========================================="
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2
echo "✅ 清理完成"

echo ""
echo "=========================================="
echo "2. 配置 WARP MDM..."
echo "=========================================="
mkdir -p /var/lib/cloudflare-warp

cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<dict>
    <key>organization</key>
    <string>vochat.teams.cloudflare.com</string>
    <key>auth_client_id</key>
    <string>${CF_ID}</string>
    <key>auth_client_secret</key>
    <string>${CF_TOKEN}</string>
</dict>
EOF
echo "✅ MDM 配置完成"

echo ""
echo "=========================================="
echo "3. 启动 warp-svc daemon..."
echo "=========================================="
nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
WARP_PID=$!
echo "✅ warp-svc 已启动 (PID: $WARP_PID)"

sleep 5

echo ""
echo "=========================================="
echo "4. 检查 daemon 状态..."
echo "=========================================="
if ps -p $WARP_PID > /dev/null 2>&1; then
    echo "✅ warp-svc 进程运行中"
else
    echo "❌ warp-svc 进程已退出"
    echo "日志："
    cat /var/log/warp-svc.log 2>/dev/null || echo "无日志"
fi

echo ""
echo "=========================================="
echo "5. 注册 WARP..."
echo "=========================================="
warp-cli register || true
echo "✅ 注册命令已执行"

echo ""
echo "=========================================="
echo "6. 设置模式并连接..."
echo "=========================================="
echo "设置 proxy 模式..."
warp-cli mode proxy || echo "⚠️ mode proxy 失败"

echo "断开旧连接..."
warp-cli disconnect 2>/dev/null || true

echo "连接 WARP..."
yes | script -q -c "warp-cli connect" /dev/null || true

echo ""
echo "=========================================="
echo "7. 等待并检查状态..."
echo "=========================================="
for i in {1..10}; do
    echo "尝试 $i/10..."
    STATUS=$(warp-cli status 2>/dev/null | head -5)
    echo "$STATUS"
    echo ""
    if echo "$STATUS" | grep -q "Connected"; then
        echo "✅ WARP 已连接！"
        break
    fi
    sleep 3
done

echo ""
echo "=========================================="
echo "8. 检查出口 IP..."
echo "=========================================="
echo -n "IPv4: "
curl -s -4 ifconfig.me || echo "获取失败"
echo ""
echo -n "IPv6: "
curl -s -6 ifconfig.me || echo "获取失败"

echo ""
echo "=========================================="
echo "9. 检查端口监听..."
echo "=========================================="
echo "TCP 端口:"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "无权限查看"

echo ""
echo "=========================================="
echo "10. WARP daemon 日志..."
echo "=========================================="
tail -30 /var/log/warp-svc.log 2>/dev/null

echo ""
echo "=========================================="
echo "11. WARP 详细状态..."
echo "=========================================="
warp-cli status

echo ""
echo "=========================================="
echo "脚本执行完毕，现在可以进入 shell 调试..."
echo "=========================================="

# 保持容器运行，但不阻塞 shell
tail -f /dev/null
