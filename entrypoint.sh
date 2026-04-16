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

mkdir -p /var/lib/cloudflare-warp/Id
mkdir -p /var/lib/cloudflare-warp/Secret

echo "${CF_ID}" > /var/lib/cloudflare-warp/Id/$(hostname)
echo "${CF_TOKEN}" > /var/lib/cloudflare-warp/Secret/$(hostname)

# 注册并连接 WARP
warp-cli set-organization "${CF_TEAM}"
warp-cli register || true
warp-cli connect

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
