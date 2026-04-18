#!/bin/bash

echo "=========================================="
echo "  WARP 调试脚本"
echo "=========================================="

# 环境变量
if [ -z "$WARP_TOKEN" ]; then
    echo "❌ WARP_TOKEN 未设置"
    echo "请设置环境变量: export WARP_TOKEN='你的teams-enroll-token'"
else
    echo "✅ WARP_TOKEN: ${WARP_TOKEN:0:50}..."
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
echo "2. 配置 WARP MDM (含 teams_enroll_token)..."
echo "=========================================="
mkdir -p /var/lib/cloudflare-warp

cat > /var/lib/cloudflare-warp/mdm.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<dict>
    <key>organization</key>
    <string>vochat.teams.cloudflare.com</string>
    <key>teams_enroll_token</key>
    <string>${WARP_TOKEN}</string>
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
echo "5. 检查 warp-cli 版本和命令..."
echo "=========================================="
warp-cli --version
echo ""
echo "warp-cli registration 子命令："
warp-cli registration --help

echo ""
echo "=========================================="
echo "6. 尝试各种注册方式..."
echo "=========================================="
echo "尝试: warp-cli registration new vochat.teams.cloudflare.com"
warp-cli registration new vochat.teams.cloudflare.com || true

echo ""
echo "=========================================="
echo "7. 检查 WARP 状态..."
echo "=========================================="
warp-cli status

echo ""
echo "=========================================="
echo "8. 检查 daemon 日志..."
echo "=========================================="
tail -50 /var/log/warp-svc.log 2>/dev/null

echo ""
echo "=========================================="
echo "9. 检查出口 IP..."
echo "=========================================="
echo -n "IPv4: "
curl -s -4 ifconfig.me || echo "获取失败"
echo ""
echo -n "IPv6: "
curl -s -6 ifconfig.me || echo "获取失败"

echo ""
echo "=========================================="
echo "脚本执行完毕，现在可以进入 shell 调试..."
echo "=========================================="

# 保持容器运行，但不阻塞 shell
tail -f /dev/null
