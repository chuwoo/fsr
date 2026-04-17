#!/bin/bash

set -e

CF_TEAM="vochat.teams.cloudflare.com"

echo "=========================================="
echo "  WARP + frpc (vochat)"
echo "=========================================="

# 检查环境变量
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
echo "✅ Client ID: ${CF_ID}"

# 清理旧进程
echo ""
echo "[2/7] 清理旧进程..."
pkill -f warp 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 配置 WARP
echo ""
echo "[3/7] 配置 WARP..."

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

# 启动 WARP daemon
echo ""
echo "[4/7] 启动 WARP daemon..."

nohup /usr/bin/warp-svc > /var/log/warp-svc.log 2>&1 &
sleep 5

echo "✅ WARP daemon 已启动"

# 先接受条款（先执行一次）
echo ""
echo "[5/7] 接受服务条款..."
yes | script -q -c "warp-cli connect" /dev/null || true

# 设置为 proxy 模式
echo ""
echo "[6/7] 设置 WARP 为 Proxy 模式..."

warp-cli mode proxy || true
sleep 3

# 断开重连
warp-cli disconnect || true
sleep 2

# 重新连接
yes | script -q -c "warp-cli connect" /dev/null || true

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

# 下载并修改 frpc 配置
echo ""
echo "[7/7] 下载 frpc 配置并启动..."
mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已下载"
    
    # 添加 SOCKS5 代理配置
    if ! grep -q "socks5_proxy_url" /etc/frp/frpc.toml; then
        echo "" >> /etc/frp/frpc.toml
        echo "# WARP SOCKS5 Proxy" >> /etc/frp/frpc.toml
        echo "socks5_proxy_url = 127.0.0.1:1080" >> /etc/frp/frpc.toml
        echo "✅ 已添加 SOCKS5 代理配置"
    fi
    
    echo ""
    echo "frpc 配置："
    cat /etc/frp/frpc.toml
    
    frpc -c /etc/frp/frpc.toml
else
    echo "⚠️ 无配置文件，保持运行"
    tail -f /dev/null
fi
