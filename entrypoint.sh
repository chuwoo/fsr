#!/bin/bash
set -e

echo "[warp-global] Starting Cloudflare WARP in global NAT mode..."

# ============================================================
# 1. 创建 TUN 设备（WARP 虚拟网卡依赖）
# ============================================================
if [ ! -e /dev/net/tun ]; then
    echo "[warp-global] Creating /dev/net/tun device..."
    sudo mkdir -p /dev/net
    sudo mknod /dev/net/tun c 10 200
    sudo chmod 600 /dev/net/tun
fi

# ============================================================
# 2. 启动 D-Bus（warp-svc 守护进程依赖）
# ============================================================
echo "[warp-global] Starting D-Bus daemon..."
sudo mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    sudo rm /run/dbus/pid
fi
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf

# ============================================================
# 3. 启动 warp-svc 后台守护进程
# ============================================================
echo "[warp-global] Starting warp-svc daemon..."
sudo warp-svc --accept-tos &

# 等待守护进程就绪
sleep "$WARP_SLEEP"

# ============================================================
# 4. 注册 WARP 客户端（仅首次）
# ============================================================
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then
        echo "[warp-global] Registering new WARP client..."
        warp-cli registration new && echo "[warp-global] WARP client registered!"
        if [ -n "$WARP_LICENSE_KEY" ]; then
            echo "[warp-global] Registering WARP+ license..."
            warp-cli registration license "$WARP_LICENSE_KEY" && echo "[warp-global] WARP+ license activated!"
        fi
    fi
else
    echo "[warp-global] WARP client already registered, skipping registration."
fi

# ============================================================
# 5. 切换到 WARP 全局模式（创建 CloudflareWARP 虚拟网卡）
# ============================================================
echo "[warp-global] Switching to WARP mode (global)..."
warp-cli --accept-tos mode warp
warp-cli --accept-tos connect

# 等待虚拟网卡创建并配置完成
sleep "$WARP_SLEEP"

# 禁用 qlog 减少日志噪音
warp-cli --accept-tos debug qlog disable

# ============================================================
# 6. 配置 nftables NAT 规则（透明全局代理）
#    原理：所有从容器发出的流量经过 CloudflareWARP 接口出去，
#          并做 masquerade 使得回程流量能正确返回。
# ============================================================
echo "[warp-global] Setting up nftables NAT rules..."

# --- IPv4 ---
sudo nft add table ip nat
sudo nft add chain ip nat WARP_NAT '{ type nat hook postrouting priority 100 ; }'
sudo nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade

sudo nft add table ip mangle
sudo nft add chain ip mangle forward '{ type filter hook forward priority mangle ; }'
# 修正 TCP MSS，避免大包在虚拟网卡的 MTU 下被丢弃
sudo nft add rule ip mangle forward tcp flags syn tcp option maxseg size set rt mtu

# --- IPv6 ---
sudo nft add table ip6 nat
sudo nft add chain ip6 nat WARP_NAT '{ type nat hook postrouting priority 100 ; }'
sudo nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade

sudo nft add table ip6 mangle
sudo nft add chain ip6 mangle forward '{ type filter hook forward priority mangle ; }'
sudo nft add rule ip6 mangle forward tcp flags syn tcp option maxseg size set rt mtu

echo "[warp-global] NAT rules configured."
echo "[warp-global] Global WARP mode is now active. All traffic goes through Cloudflare WARP."

# 验证连接
echo "[warp-global] Verifying WARP connection..."
warp-cli --accept-tos status

# 保持容器运行
tail -f /dev/null
