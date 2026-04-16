#!/bin/bash

set -e

echo "=========================================="
echo "  Cloudflare Tunnel + frpc 启动脚本"
echo "=========================================="

# 调试信息
echo ""
echo "[DEBUG] PATH: $PATH"
echo "[DEBUG] which cloudflared: $(which cloudflared 2>/dev/null || echo 'not found')"
echo "[DEBUG] which frpc: $(which frpc 2>/dev/null || echo 'not found')"

# 检查环境变量
echo ""
echo "[1/5] 检查环境变量..."

if [ -z "$CF_ID" ]; then
    echo "❌ 错误：CF_ID (Tunnel ID) 未设置"
    exit 1
fi

if [ -z "$CF_TOKEN" ]; then
    echo "❌ 错误：CF_TOKEN (Tunnel Token) 未设置"
    exit 1
fi

echo "✅ CF_ID: ${CF_ID}"
echo "✅ CF_TOKEN: 已设置"

# 检查 cloudflared 是否可用
echo ""
echo "[2/5] 检查 cloudflared..."

if ! command -v cloudflared &> /dev/null; then
    echo "❌ cloudflared 未安装，尝试手动安装..."
    ARCH=$(dpkg --print-architecture)
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb \
        -o /tmp/cloudflared.deb
    dpkg -i /tmp/cloudflared.deb
    rm /tmp/cloudflared.deb
fi

cloudflared --version

# 启动 Cloudflare Tunnel
echo ""
echo "[3/5] 启动 Cloudflare Tunnel..."

# 清理旧的 tunnel 进程
pkill -f cloudflared 2>/dev/null || true
sleep 2

# 检查端口占用
netstat -tuln 2>/dev/null || ss -tuln

# 后台启动 cloudflared tunnel
nohup cloudflared tunnel run --id "${CF_ID}" --token "${CF_TOKEN}" > /var/log/cloudflared.log 2>&1 &
CLOUDFLARED_PID=$!

echo "✅ Cloudflare Tunnel 已启动 (PID: $CLOUDFLARED_PID)"

# 等待 tunnel 建立
echo "等待 Tunnel 建立..."
for i in {1..15}; do
    sleep 2
    if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
        echo "✅ Tunnel 运行正常 (${i}*2秒)"
        break
    else
        echo "⏳ 等待中... (${i}/15)"
    fi
done

# 检查日志
echo ""
echo "[DEBUG] Tunnel 日志："
tail -20 /var/log/cloudflared.log 2>/dev/null || true

# 下载 frpc 配置文件
echo ""
echo "[4/5] 下载 frpc 配置文件..."

mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    FRPC_URL="${FRP_REPO}${FRP_CON}"
    echo "📥 下载地址: ${FRPC_URL}"
    
    curl -fsSL "${FRPC_URL}" -o /etc/frp/frpc.toml
    
    if [ -f /etc/frp/frpc.toml ]; then
        echo "✅ 配置文件已保存"
    else
        echo "❌ 配置文件下载失败"
        exit 1
    fi
else
    echo "⚠️ 警告：FRP_REPO 或 FRP_CON 未设置，跳过下载"
fi

echo ""
echo "frpc 配置文件内容："
cat /etc/frp/frpc.toml 2>/dev/null || echo "（配置文件不存在）"

# 启动 frpc
echo ""
echo "[5/5] 启动 frpc..."

if [ -f /etc/frp/frpc.toml ]; then
    nohup frpc -c /etc/frp/frpc.toml > /var/log/frpc.log 2>&1 &
    FRPC_PID=$!
    echo "✅ frpc 已启动 (PID: $FRPC_PID)"
else
    echo "⚠️ 跳过 frpc（无配置文件）"
    FRPC_PID=""
fi

# 监控进程
echo ""
echo "=========================================="
echo "  进入监控模式..."
echo "=========================================="

# 信号处理
cleanup() {
    echo "收到停止信号，清理进程..."
    [ -n "$CLOUDFLARED_PID" ] && kill $CLOUDFLARED_PID 2>/dev/null || true
    [ -n "$FRPC_PID" ] && kill $FRPC_PID 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# 监控循环
while true; do
    sleep 30
    
    if [ -n "$CLOUDFLARED_PID" ]; then
        if ! ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
            echo "⚠️ Cloudflare Tunnel 已退出，重新启动..."
            nohup cloudflared tunnel run --id "${CF_ID}" --token "${CF_TOKEN}" > /var/log/cloudflared.log 2>&1 &
            CLOUDFLARED_PID=$!
        fi
    fi
    
    if [ -n "$FRPC_PID" ]; then
        if ! ps -p $FRPC_PID > /dev/null 2>&1; then
            echo "⚠️ frpc 已退出，重新启动..."
            nohup frpc -c /etc/frp/frpc.toml > /var/log/frpc.log 2>&1 &
            FRPC_PID=$!
        fi
    fi
    
    echo "✅ $(date '+%Y-%m-%d %H:%M:%S') - 运行中"
done
