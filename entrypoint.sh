#!/bin/bash

set -e

echo "=========================================="
echo "  Cloudflare Tunnel + frpc"
echo "=========================================="

# 检查环境变量
echo ""
echo "[1/4] 检查环境变量..."

if [ -z "$CF_ID" ]; then
    echo "❌ 错误：CF_ID 未设置"
    exit 1
fi

if [ -z "$CF_TOKEN" ]; then
    echo "❌ 错误：CF_TOKEN 未设置"
    exit 1
fi

echo "✅ CF_ID: ${CF_ID}"
echo "✅ CF_TOKEN: 已设置"

# 清理旧进程
echo ""
echo "[2/4] 清理旧进程..."
pkill -f cloudflared 2>/dev/null || true
pkill -f frpc 2>/dev/null || true
sleep 2

# 启动 Cloudflare Tunnel（只用 --token 参数）
echo ""
echo "[3/4] 启动 Cloudflare Tunnel..."

nohup cloudflared tunnel run --token "${CF_TOKEN}" > /var/log/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

echo "✅ Tunnel 已启动 (PID: $CLOUDFLARED_PID)"

# 等待连接
sleep 10

# 检查状态
if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
    echo "✅ Tunnel 运行正常"
else
    echo "❌ Tunnel 启动失败"
    echo "日志内容："
    cat /var/log/cloudflared.log
    exit 1
fi

# 下载 frpc 配置
echo ""
echo "[4/4] 下载并启动 frpc..."

mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    echo "📥 下载: ${FRP_REPO}${FRP_CON}"
    curl -fsSL "${FRP_REPO}${FRP_CON}" -o /etc/frp/frpc.toml || {
        echo "❌ 配置下载失败"
        exit 1
    }
fi

if [ -f /etc/frp/frpc.toml ]; then
    echo "✅ 配置文件已保存"
    nohup frpc -c /etc/frp/frpc.toml > /var/log/frpc.log 2>&1 &
    FRPC_PID=$!
    echo "✅ frpc 已启动 (PID: $FRPC_PID)"
else
    echo "⚠️ 无配置文件，跳过 frpc"
    FRPC_PID=""
fi

# 监控
echo ""
echo "=========================================="
echo "  监控中... (PID: cloudflared=$CLOUDFLARED_PID frpc=$FRPC_PID)"
echo "=========================================="

trap 'kill $CLOUDFLARED_PID $FRPC_PID 2>/dev/null; exit' SIGTERM SIGINT

while true; do
    sleep 30
    
    if ! ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
        echo "$(date '+%H:%M:%S') ⚠️ Tunnel 重启..."
        nohup cloudflared tunnel run --token "${CF_TOKEN}" > /var/log/cloudflared.log 2>&1 &
        CLOUDFLARED_PID=$!
    fi
    
    if [ -n "$FRPC_PID" ] && ! ps -p $FRPC_PID > /dev/null 2>&1; then
        echo "$(date '+%H:%M:%S') ⚠️ frpc 重启..."
        nohup frpc -c /etc/frp/frpc.toml > /var/log/frpc.log 2>&1 &
        FRPC_PID=$!
    fi
    
    echo "$(date '+%H:%M:%S') ✅ 运行中"
done
