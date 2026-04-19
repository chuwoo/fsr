FROM alpine:3.22

LABEL maintainer="WARP-IPv6-frpc" \
    org.opencontainers.image.title="Docker-WARP-IPv6-frpc" \
    org.opencontainers.image.description="Integrated sing-box WARP IPv6 tunnel with frpc."

# 安装依赖：增加了 netcat-openbsd 用于检测端口就绪
RUN apk update && apk upgrade \
    && apk add --no-cache curl openssl jq tar gcompat netcat-openbsd \
    && rm -rf /var/cache/apk/*

# 下载 sing-box
RUN set -e; \
    cd /tmp && \
    ARCH='amd64' && \
    echo "Downloading sing-box for linux-${ARCH}..." && \
    RELEASE_URL=$(curl -fsSL -X GET "https://api.github.com/repos/SagerNet/sing-box/releases" | \
        jq -r '[.[] | select(.prerelease == true or (.tag_name | contains("beta")) or (.tag_name | contains("rc")))] | .[0].assets[] | select(.name | contains("linux-'${ARCH}'.tar.gz")) | .browser_download_url' | head -1) && \
    if [ -z "$RELEASE_URL" ] || [ "$RELEASE_URL" = "null" ]; then \
        echo "No beta found, using latest stable release..." && \
        RELEASE_URL=$(curl -fsSL -X GET "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | \
            jq -r '.assets[] | select(.name | contains("linux-'${ARCH}'.tar.gz")) | .browser_download_url' | head -1); \
    fi && \
    if [ -z "$RELEASE_URL" ] || [ "$RELEASE_URL" = "null" ]; then \
        echo "No release found for architecture: ${ARCH}" && exit 1; \
    fi && \
    echo "Downloading from: ${RELEASE_URL}" && \
    curl -fsSL "$RELEASE_URL" -o singbox.tar.gz && \
    tar xzf singbox.tar.gz && \
    find . -name "sing-box" -type f -executable -exec mv {} /usr/bin/sing-box \; && \
    chmod +x /usr/bin/sing-box && \
    mkdir -p /etc/sing-box && \
    rm -rf /tmp/*

# 下载 frpc 0.68.1
ARG FRP_VERSION=0.68.1
RUN set -e; \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64) FRP_ARCH="amd64" ;; \
        aarch64) FRP_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH"; exit 1 ;; \
    esac && \
    echo "Downloading frpc v${FRP_VERSION} for linux_${FRP_ARCH}..." && \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz" | \
    tar xz --strip-components=1 -C /usr/local/bin "frp_${FRP_VERSION}_linux_${FRP_ARCH}/frpc" && \
    chmod +x /usr/local/bin/frpc

COPY entrypoint.sh /run/entrypoint.sh
RUN chmod +x /run/entrypoint.sh

ENTRYPOINT ["/run/entrypoint.sh"]
