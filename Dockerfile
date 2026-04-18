ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG WARP_VERSION
ARG COMMIT_SHA

LABEL org.opencontainers.image.authors="warp-global"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

# ─── 安装依赖 ───
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc nftables && \
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && \
    apt-get autoremove -y && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

# ─── 内联 entrypoint.sh ───
RUN printf '#!/bin/bash\nset -e\n\
echo "[warp-global] Starting Cloudflare WARP in global NAT mode..."\n\
\n\
if [ ! -e /dev/net/tun ]; then\n\
    echo "[warp-global] Creating /dev/net/tun device..."\n\
    sudo mkdir -p /dev/net\n\
    sudo mknod /dev/net/tun c 10 200\n\
    sudo chmod 600 /dev/net/tun\n\
fi\n\
\n\
echo "[warp-global] Starting D-Bus daemon..."\n\
sudo mkdir -p /run/dbus\n\
if [ -f /run/dbus/pid ]; then\n\
    sudo rm /run/dbus/pid\n\
fi\n\
sudo dbus-daemon --config-file=/usr/share/dbus-1/system.conf\n\
\n\
echo "[warp-global] Starting warp-svc daemon..."\n\
sudo warp-svc --accept-tos &\n\
sleep "$WARP_SLEEP"\n\
\n\
if [ ! -f /var/lib/cloudflare-warp/reg.json ]; then\n\
    if [ ! -f /var/lib/cloudflare-warp/mdm.xml ] || [ -n "$REGISTER_WHEN_MDM_EXISTS" ]; then\n\
        echo "[warp-global] Registering new WARP client..."\n\
        warp-cli registration new && echo "[warp-global] WARP client registered!"\n\
        if [ -n "$WARP_LICENSE_KEY" ]; then\n\
            echo "[warp-global] Registering WARP+ license..."\n\
            warp-cli registration license "$WARP_LICENSE_KEY" && echo "[warp-global] WARP+ license activated!"\n\
        fi\n\
    fi\n\
else\n\
    echo "[warp-global] WARP client already registered, skipping registration."\n\
fi\n\
\n\
echo "[warp-global] Switching to WARP mode (global)..."\n\
warp-cli --accept-tos mode warp\n\
warp-cli --accept-tos connect\n\
sleep "$WARP_SLEEP"\n\
warp-cli --accept-tos debug qlog disable\n\
\n\
echo "[warp-global] Setting up nftables NAT rules..."\n\
sudo nft add table ip nat\n\
sudo nft add chain ip nat WARP_NAT "{ type nat hook postrouting priority 100 ; }"\n\
sudo nft add rule ip nat WARP_NAT oifname "CloudflareWARP" masquerade\n\
sudo nft add table ip mangle\n\
sudo nft add chain ip mangle forward "{ type filter hook forward priority mangle ; }"\n\
sudo nft add rule ip mangle forward tcp flags syn tcp option maxseg size set rt mtu\n\
sudo nft add table ip6 nat\n\
sudo nft add chain ip6 nat WARP_NAT "{ type nat hook postrouting priority 100 ; }"\n\
sudo nft add rule ip6 nat WARP_NAT oifname "CloudflareWARP" masquerade\n\
sudo nft add table ip6 mangle\n\
sudo nft add chain ip6 mangle forward "{ type filter hook forward priority mangle ; }"\n\
sudo nft add rule ip6 mangle forward tcp flags syn tcp option maxseg size set rt mtu\n\
\n\
echo "[warp-global] NAT rules configured."\n\
echo "[warp-global] Global WARP mode is now active. All traffic goes through Cloudflare WARP."\n\
echo "[warp-global] Verifying WARP connection..."\n\
warp-cli --accept-tos status\n\
\n\
tail -f /dev/null\n' > /entrypoint.sh && chmod +x /entrypoint.sh

# ─── 内联 healthcheck ───
RUN mkdir -p /healthcheck && \
    printf '#!/bin/bash\nset -e\npgrep -x "warp-svc" > /dev/null || { echo "warp-svc not running"; exit 1; }\nip link show CloudflareWARP > /dev/null 2>&1 || { echo "CloudflareWARP not found"; exit 1; }\necho "WARP is healthy"\nexit 0\n' > /healthcheck/index.sh && \
    chmod +x /healthcheck/index.sh

USER warp

RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV WARP_SLEEP=2
ENV WARP_LICENSE_KEY=
ENV REGISTER_WHEN_MDM_EXISTS=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
