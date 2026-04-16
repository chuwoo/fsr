#!/bin/bash
set -euo pipefail

WG_CONF="/etc/wireguard/wgcf-profile.conf"
FRPC_CONF="/etc/frp/frpc.toml"

echo "=============================="
echo "  WARP + frpc 容器启动"
echo "=============================="

# ---- 检查配置 ----
if [ ! -f "$WG_CONF" ]; then
    echo "❌ 缺少 $WG_CONF"
    echo "   请先用 wgcf 生成并挂载到容器"
    exit 1
fi
if [ ! -f "$FRPC_CONF" ]; then
    echo "❌ 缺少 $FRPC_CONF"
    exit 1
fi

# ---- 解析 wgcf 配置 ----
echo "[1/5] 解析 WireGuard 配置..."
PRIVATE_KEY=$(grep '^PrivateKey' "$WG_CONF" | awk -F'= ' '{print $2}')
PEER_PUBLIC_KEY=$(grep '^PublicKey' "$WG_CONF" | awk -F'= ' '{print $2}')
ENDPOINT=$(grep '^Endpoint' "$WG_CONF" | awk -F'= ' '{print $2}')
WG_IPV4=$(grep '^Address' "$WG_CONF" | sed 's/.*= //' | sed 's/,.*//' | tr -d ' ')
WG_IPV6=$(grep '^Address' "$WG_CONF" | sed 's/.*= //' | sed 's/.*,\s*//' | tr -d ' ')

echo "   IPv4: $WG_IPV4"
echo "   IPv6: $WG_IPV6"
echo "   Endpoint: $ENDPOINT"

# ---- 启动 BoringTun ----
echo "[2/5] 启动 BoringTun..."
boringtun-cli --disable-drop-privileges --log-level=info wg0

# ---- 配置 wg0 接口 ----
echo "[3/5] 配置 wg0..."
wg set wg0 \
    private-key <(echo "$PRIVATE_KEY") \
    peer "$PEER_PUBLIC_KEY" \
    endpoint "$ENDPOINT" \
    allowed-ips "0.0.0.0/0, ::/0" \
    persistent-keepalive 25

ip addr add "$WG_IPV4/32" dev wg0 2>/dev/null || true
ip addr add "${WG_IPV6}/128" dev wg0 2>/dev/null || true
ip link set mtu 1280 dev wg0
ip link set wg0 up

echo "   wg0 状态:"
wg show wg0 | head -3

# ---- 策略路由: frpc 流量走 WARP ----
echo "[4/5] 配置策略路由..."

grep -q '^200 warp' /etc/iproute2/rt_tables 2>/dev/null || echo "200 warp" >> /etc/iproute2/rt_tables

# WARP 默认路由（走 warp 路由表，不改主表）
ip route add default dev wg0 table warp 2>/dev/null || true
ip -6 route add default dev wg0 table warp 2>/dev/null || true

# 打标记的包走 warp 表
ip rule add fwmark 0x1 table warp priority 100 2>/dev/null || true
ip -6 rule add fwmark 0x1 table warp priority 100 2>/dev/null || true

# WARP 源地址的回包也走 warp 表
ip rule add from "$WG_IPV4" table warp priority 100 2>/dev/null || true
ip -6 rule add from "$WG_IPV6" table warp priority 100 2>/dev/null || true

# 所有出站 TCP/UDP 打标记 → 走 WARP
iptables  -t mangle -A OUTPUT -p tcp -j MARK --set-mark 0x1
iptables  -t mangle -A OUTPUT -p udp -j MARK --set-mark 0x1
ip6tables -t mangle -A OUTPUT -p tcp -j MARK --set-mark 0x1
ip6tables -t mangle -A OUTPUT -p udp -j MARK --set-mark 0x1

# BoringTun 自身的流量不打标记（防环路）
iptables  -t mangle -I OUTPUT -o wg0 -j MARK --set-mark 0x0
ip6tables -t mangle -I OUTPUT -o wg0 -j MARK --set-mark 0x0

echo "   ✅ 策略路由就绪"

# ---- 验证 IPv6 ----
echo "[5/5] 验证网络..."
ping6 -c1 -W3 2606:4700:4700::1111 >/dev/null 2>&1 \
    && echo "   ✅ IPv6 可达" \
    || echo "   ⚠️ IPv6 暂不可达（隧道建立中）"

echo ""
echo "=============================="
echo "  启动 frpc"
echo "=============================="
exec frpc -c "$FRPC_CONF"
