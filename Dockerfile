FROM debian:12-slim

ARG FRP_VERSION=0.68.1

# 运行时必需的环境变量
ENV CF_TEAM="vochat.teams.cloudflare.com"
ENV CF_ID=""
ENV CF_TOKEN=""
ENV FRP_REPO=""
ENV FRP_CON=""

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates bash gnupg bsdutils \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
    https://pkg.cloudflareclient.com/ bookworm main" \
    > /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && apt-get install -y --no-install-recommends cloudflare-warp && \
    ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "frp_${FRP_VERSION}_linux_${ARCH}/frpc" && \
    chmod +x /usr/local/bin/frpc && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 建议挂载的目录（持久化注册信息 + 配置）
VOLUME ["/var/lib/cloudflare-warp", "/etc/frp"]

ENTRYPOINT ["/entrypoint.sh"]
