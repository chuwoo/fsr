FROM alpine:3.22

LABEL maintainer="WARP-IPv6-Only" \
    org.opencontainers.image.title="Docker-Warp-Socks-IPv6" \
    org.opencontainers.image.description="Connect to CloudFlare WARP IPv6 only, exposing socks5 proxy."

RUN apk update && apk upgrade \
    && apk add --no-cache curl openssl jq tar gcompat \
    && rm -rf /var/cache/apk/*

RUN set -e; \
    cd /tmp && \
    case $(arch) in \
        x86_64)  ARCH='amd64' ;; \
        aarch64) ARCH='arm64' ;; \
        armv7l)  ARCH='armv7' ;; \
        armv6l)  ARCH='armv6' ;; \
        arm)     ARCH='armv7' ;; \
        ppc64le) ARCH='ppc64le' ;; \
        s390x)   ARCH='s390x' ;; \
        riscv64) ARCH='riscv64' ;; \
        *)       echo "Unsupported architecture $(arch)" && exit 1 ;; \
    esac && \
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

COPY entrypoint.sh /run/entrypoint.sh
RUN chmod +x /run/entrypoint.sh
ENTRYPOINT ["/run/entrypoint.sh"]

CMD ["rws-cli-v5"]
