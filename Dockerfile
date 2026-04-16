FROM debian:12-slim

ARG FRP_VERSION=0.68.1

ENV CF_ID=""
ENV CF_TOKEN=""
ENV FRP_CON=""
ENV FRP_REPO=""

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates bash jq gnupg iproute2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 安装 cloudflared
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb \
    -o /tmp/cloudflared.deb \
    && dpkg -i /tmp/cloudflared.deb \
    && rm /tmp/cloudflared.deb

# 安装 frpc
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${ARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "frp_${FRP_VERSION}_linux_${ARCH}/frpc" \
    && chmod +x /usr/local/bin/frpc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
