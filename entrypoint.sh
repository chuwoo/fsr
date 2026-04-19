#!/bin/sh

set -e

sleep 3

_WARP_SERVER=engage.cloudflareclient.com
_WARP_PORT=2408
_NET_PORT=9091

WARP_SERVER="${WARP_SERVER:-$_WARP_SERVER}"
WARP_PORT="${WARP_PORT:-$_WARP_PORT}"
NET_PORT="${NET_PORT:-$_NET_PORT}"

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

# 【关键修改】路由规则：
# 1. IPv4 全部走 direct-out（直连，不走 WARP）
# 2. IPv6 全部走 WARP 隧道
# 3. 私有地址走 direct-out
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
                    "0.0.0.0/8",
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
            },
            {
                "ip_cidr": [
                    "0.0.0.0/0"
                ],
                "outbound": "direct-out"
            }
        ],
        "auto_detect_interface": true,
        "final": "WARP"
'

# 【关键修改】WireGuard 端点：
# 1. address 只用 IPv6 地址（去掉 IPv4）
# 2. allowed_ips 只路由 IPv6（::/0），IPv4 不走隧道
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
echo " WARP IPv6-Only Mode"
echo " IPv4 → direct (container native network)"
echo " IPv6 → WARP tunnel → Cloudflare edge"
echo " Proxy: socks5://127.0.0.1:${NET_PORT}"
echo "============================================"

if [ ! -e "/usr/bin/rws-cli-v5" ]; then
    echo "sing-box -c /etc/sing-box/config.json run" > /usr/bin/rws-cli-v5 && chmod +x /usr/bin/rws-cli-v5
fi

exec "$@"
