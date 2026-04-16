FRPC_CONF="/etc/frp/frpc.toml"

echo "=============================="
echo "  WARP + frpc 容器启动"
echo "=============================="

# ---- 检查环境变量 ----
for VAR in CF_ID CF_TOKEN FRP_CON FRP_REPO; do
    [ -z "${!VAR:-}" ] && echo "❌ 缺少环境变量: $VAR" && exit 1
done

# ---- 启动 warp-svc ----
echo "[1] 启动 warp-svc..."
warp-svc &
sleep 3

# ---- 查看版本和帮助 ----
echo "[2] warp-cli 版本:"
warp-cli --version 2>&1 || true
echo "[2] warp-cli 命令列表:"
warp-cli --help 2>&1 || true

# ---- 注册 ----
echo "[3] 注册 WARP..."
warp-cli --accept-tos registration new 2>&1
echo "   注册结果: $?"

sleep 1

# ---- 状态 ----
echo "[4] WARP 状态:"
warp-cli status 2>&1 || true

# ---- 设置模式（尝试所有可能的命令）----
echo "[5] 设置代理模式..."
warp-cli mode proxy 2>&1 && echo "   mode proxy OK" || echo "   mode proxy 失败"
warp-cli proxy port 40000 2>&1 && echo "   proxy port OK" || echo "   proxy port 失败"

# ---- 连接 ----
echo "[6] 连接 WARP..."
warp-cli connect 2>&1 || true

sleep 5
echo "[7] 连接后状态:"
warp-cli status 2>&1 || true

echo "[8] IPv6 检测:"
curl -6 -s --max-time 10 https://api64.ipify.org 2>/dev/null || echo "不可达"

echo ""
echo "=============================="
echo "  诊断完成，容器保持运行"
echo "=============================="
sleep 3600
