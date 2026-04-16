#!/bin/bash

set -e

echo "=========================================="
echo "  Cloudflare Tunnel + frpc 启动脚本"
echo "=========================================="

# ============================================
# 1. 检查环境变量
# ============================================
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

# ============================================
# 2. 启动 Cloudflare Tunnel
# ============================================
echo ""
echo "[2/5] 启动 Cloudflare Tunnel..."

# 清理旧的 tunnel 进程
pkill -f cloudflared 2>/dev/null || true
sleep 1

# 后台启动 cloudflared tunnel
cloudflared tunnel run --id "${CF_ID}" --token "${CF_TOKEN}" &
CLOUDFLARED_PID=$!

echo "✅ Cloudflare Tunnel 已启动 (PID: $CLOUDFLARED_PID)"

# 等待 tunnel 建立
sleep 10

# 检查 tunnel 状态
if ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
    echo "✅ Tunnel 运行正常"
else
    echo "❌ Tunnel 启动失败"
    exit 1
fi

# ============================================
# 3. 下载 frpc 配置文件
# ============================================
echo ""
echo "[3/5] 下载 frpc 配置文件..."

mkdir -p /etc/frp

if [ -n "$FRP_REPO" ] && [ -n "$FRP_CON" ]; then
    FRPC_URL="${FRP_REPO}${FRP_CON}"
    echo "📥 下载地址: ${FRPC_URL}"
    
    curl -fsSL "${FRPC_URL}" -o /etc/frp/frpc.toml
    
    if [ -f /etc/frp/frpc.toml ]; then
        echo "✅ 配置文件已保存到 /etc/frp/frpc.toml"
    else
        echo "❌ 配置文件下载失败"
        exit 1
    fi
else
    echo "⚠️ 警告：FRP_REPO 或 FRP_CON 未设置，跳过下载"
fi

# 显示配置文件内容（调试用）
echo ""
echo "frpc 配置文件内容："
cat /etc/frp/frpc.toml 2>/dev/null || echo "（配置文件不存在）"

# ============================================
# 4. 启动 frpc
# ============================================
echo ""
echo "[4/5] 启动 frpc..."

frpc -c /etc/frp/frpc.toml &
FRPC_PID=$!

echo "✅ frpc 已启动 (PID: $FRPC_PID)"

# ============================================
# 5. 监控进程
# ============================================
echo ""
echo "[5/5] 进入监控模式..."

# trap 信号处理，确保退出时清理进程
trap 'kill $CLOUDFLARED_PID $FRPC_PID 2>/dev/null; exit' SIGTERM SIGINT

# 监控进程状态
while true; do
    sleep 30
    
    # 检查 frpc
    if ! ps -p $FRPC_PID > /dev/null 2>&1; then
        echo "⚠️ frpc 进程已退出，尝试重启..."
        frpc -c /etc/frp/frpc.toml &
        FRPC_PID=$!
    fi
    
    # 检查 cloudflared
    if ! ps -p $CLOUDFLARED_PID > /dev/null 2>&1; then
        echo "⚠️ Cloudflare Tunnel 已退出，尝试重启..."
        cloudflared tunnel run --id "${CF_ID}" --token "${CF_TOKEN}" &
        CLOUDFLARED_PID=$!
    fi
    
    echo "✅ $(date '+%Y-%m-%d %H:%M:%S') - frpc: 运行中, tunnel: 运行中"
done
