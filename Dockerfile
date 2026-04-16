FROM debian:12-slim

ARG FRP_VERSION=0.68.1

# 运行时传入的四个环境变量
ENV CF_ID=""
ENV CF_TOKEN=""
ENV FRP_CON=""
ENV FRP_REPO=""

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates bash jq gnupg \
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
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
