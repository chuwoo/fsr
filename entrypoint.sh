#!/bin/sh

set -e

sleep 3

_WARP_SERVER=engage.cloudflareclient.com
_WARP_PORT=2408
_NET_PORT=9091

WARP_SERVER="${WARP_SERVER:-$_WARP_SERVER}"
WARP_PORT="${WARP_PORT:-$_WARP_PORT}"
NET_PORT="${NET_PORT:-$_NET_PORT}"
export WARP_SERVER WARP_PORT NET_PORT
# ==========================================
# 第一阶段：构建 WARP (sing-box) 配置
# ==========================================

RESPONSE=$(curl -fsSL bit.ly/create-cloudflare-warp | sh -s)
CF_CLIENT_ID=$(echo "$RESPONSE" | grep -o '"client":"[^"]*' | cut -d'"' -f4 | head -n 1)
CF_ADDR_V4=$(echo "$RESPONSE" | grep -o '"v4":"[^"]*' | cut -d'"' -f4 | tail -n 1)
CF_ADDR_V6=$(echo "$RESPONSE" | grep -o '"v6":"[^"]*' | cut -d'"' -f4 | tail -n 1)

CF_PUBLIC_KEY=$(echo "$RESPONSE" | grep -o '"key":"[^"]*' | cut -d'"' -f4 | head -n 1)
CF_PRIVATE_KEY=$(echo "$RESPONSE" | grep -o '"secret":"[^"]*' | cut -d'"' -f4 | head -n 1)

reserved=$(echo "$CF_CLIENT_ID" | base64 -d | od -An -t u1 | awk '{print "["$1", "$2", "$3"]"}' | head -n 1)

if [ -n "$SOCK_USER" ] && [ -n "$SOCK_PWD" ]; then
AUTH_PART='
    "users": [
        {
            "username": "'"$SOCK_USER"'",
            "password": "'"$SOCK_PWD"'",
        }
    ],
'
else
    AUTH_PART=""
fi

DNS_PART='
        "servers": [
            {
                "tag": "remote",
                "type": "tls",
                "server": "dns.quad9.net",
                "domain_resolver": "local",
                "detour": "direct-out"
            },
            {
                "tag": "local",
                "type": "udp",
                "server": "119.29.29.29",
                "detour": "direct-out"
            }
        ],
        "final": "remote",
        "reverse_mapping": true
'

ROUTE_PART='
        "default_domain_resolver": {
            "server": "local",
            "rewrite_ttl": 60
        },
        "rules": [
            {
                "inbound": "mixed-in",
                "action": "sniff"
            },
            {
                "protocol": "dns",
                "action": "hijack-dns"
            },
            {
                "ip_is_private": true,
                "outbound": "direct-out"
            },
            {
                "ip_cidr": [
                    "0.0.0.0/0",
                    "10.0.0.0/8",
                    "127.0.0.0/8",
                    "169.254.0.0/16",
                    "172.16.0.0/12",
                    "192.168.0.0/16",
                    "224.0.0.0/4",
                    "240.0.0.0/4",
                    "52.80.0.0/16",
                    "112.95.0.0/16"
                ],
                "outbound": "direct-out"
            }
        ],
        "auto_detect_interface": true,
        "final": "WARP"
'

PROXY_PART='
    "endpoints": [
        {
            "tag": "WARP",
            "type": "wireguard",
            "address": [
                "'"${CF_ADDR_V6}"'/128"
            ],
            "private_key": "'"$CF_PRIVATE_KEY"'",
            "peers": [
                {
                    "address": "'"$WARP_SERVER"'",
                    "port": '"$WARP_PORT"',
                    "public_key": "'"$CF_PUBLIC_KEY"'",
                    "allowed_ips": [
                        "::/0"
                    ],
                    "persistent_keepalive_interval": 30,
                    "reserved": '"$reserved"'
                }
            ],
            "mtu": 1408,
            "udp_fragment": true
        }
    ],
'

cat <<EOF | tee /etc/sing-box/config.json
{
    "dns": {
 $DNS_PART
    },
    "route": {
 $ROUTE_PART
    },
    "inbounds": [
        {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "::",
 $AUTH_PART
            "listen_port": $NET_PORT
        }
    ],
 $PROXY_PART
    "outbounds": [
        {
            "tag": "direct-out",
            "type": "direct",
            "udp_fragment": true
        }
    ]
}
EOF

echo "============================================"
echo " WARP IPv6-Only Mode Initialized"
echo " IPv4 -> direct (container native network)"
echo " IPv6 -> WARP tunnel -> Cloudflare edge"
echo " Local Proxy: socks5://127.0.0.1:${NET_PORT}"
echo "============================================"

# ==========================================
# 第二阶段：启动 WARP 并等待就绪
# ==========================================

echo "🚀 后台启动 sing-box..."
sing-box -c /etc/sing-box/config.json run &
SINGBOX_PID=$!

# 使用 nc 轮询检测本地代理端口是否可用
echo "⏳ 等待 WARP 代理端口 ${NET_PORT} 就绪..."
timeout 30 sh -c 'until nc -z 127.0.0.1 $NET_PORT 2>/dev/null; do sleep 1; done' || {
    echo "❌ WARP (sing-box) 启动超时，请检查日志！"
    exit 1
}
echo "✅ WARP 代理已就绪"

# ==========================================
# 第三阶段：下载并处理 frpc 配置
# ==========================================

if [ -z "$FRP_REPO" ] || [ -z "$FRP_CONF" ]; then
    echo "❌ 缺少必要环境变量！"
    echo "   请设置 -e FRP_REPO='你的raw基础路径'"
    echo "   请设置 -e FRP_CONF='你的配置文件名'"
    exit 1
fi

# 容错处理：去掉末尾斜杠和开头斜杠，防止拼接出 //frpc.toml 这种格式
FRP_REPO_CLEAN="${FRP_REPO%/}"
FRP_CONF_CLEAN="${FRP_CONF#/}"
FRP_URL="${FRP_REPO_CLEAN}/${FRP_CONF_CLEAN}"

mkdir -p /etc/frp
echo "⬇️  正在下载 frpc 配置: $FRP_URL"
curl -fsSL "$FRP_URL" -o /etc/frp/frpc.toml || {
    echo "❌ frpc 配置下载失败！请检查网络或 URL 是否正确。"
    exit 1
}

echo "✅ 配置下载成功"

# 【核心魔法】：
# 先删除可能存在的旧 proxySettings 防止 TOML 重复键报错，然后在末尾强行注入代理配置
sed -i '/^\[transport\.proxySettings\]/,+3d' /etc/frp/frpc.toml

echo -e "\n[transport.proxySettings]\ntype = \"socks5\"\naddress = \"127.0.0.1\"\nport = ${NET_PORT}" >> /etc/frp/frpc.toml

echo "============================================"
echo "🛠️ 最终生效的 frpc 配置如下："
cat /etc/frp/frpc.toml
echo "============================================"

# ==========================================
# 第四阶段：前台启动 frpc (接管容器生命周期)
# ==========================================

echo "🚀 启动 frpc..."
exec frpc -c /etc/frp/frpc.toml
