#!/bin/bash
set -e

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

# 环境变量检查
if [ -z "$CF_ID" ] || [ -z "$CF_TOKEN" ]; then
    echo "❌ 请设置 CF_ID 和 CF_TOKEN"
    exit 1
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
sleep 3

# 注册设备（关键步骤！只在第一次或 reg.json 不存在时执行）
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    echo "正在注册设备到 Cloudflare Teams..."
    warp-cli register || true
fi

# 设置模式并连接（使用 script 模拟 tty，解决非交互环境提示问题）
warp-cli mode warp || true
warp-cli disconnect 2>/dev/null || true
sleep 2

echo "正在连接 WARP..."
yes | script -q -c "warp-cli connect" /dev/null || true

# 等待 WARP 真正 Connected（最多等 30 秒）
echo "等待 WARP 连接成功..."
for i in {1..15}; do
    STATUS=$(warp-cli status 2>/dev/null | grep -oP 'Status: \K\w+' || echo "Disconnected")
    if [ "$STATUS" = "Connected" ]; then
        echo "✅ WARP 已连接"
        break
    fi
    sleep 2
done

if [ "$STATUS" != "Connected" ]; then
    echo "⚠️ WARP 连接超时，请检查日志 /var/log/warp-svc.log"
fi

# 显示出口 IP（验证是否走 WARP）
echo "出口 IP："
echo -n "IPv4: "; curl -s -4 ifconfig.me || echo "失败"
echo ""
echo -n "IPv6: "; curl -s -6 ifconfig.me || echo "无 IPv6"

# 下载 frpc 配置（如果提供了 FRP_REPO + FRP_CON）
mkdir -p /etc/frp
if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    echo "正在下载 frpc 配置: ${FRP_REPO}${FRP_CON}"
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml || echo "⚠️ 配置下载失败"
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 使用配置文件 /etc/frp/frpc.toml"
    cat /etc/frp/frpc.toml
    echo "启动 frpc..."
    exec frpc -c /etc/frp/frpc.toml   # 用 exec 替换进程，优雅退出
else
    echo "❌ 未找到 frpc.toml，容器将保持运行（便于调试）"
    tail -f /dev/null
fi
