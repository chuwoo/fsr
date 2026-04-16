# ============================================================
# WARP + frpc — Alpine 最小化镜像
# BoringTun (Cloudflare 用户态 WireGuard) + frpc
# ============================================================

# ---------- Stage 1: 编译 BoringTun ----------
FROM rust:1.77-alpine AS builder

RUN apk add --no-cache musl-dev

RUN cargo install boringtun-cli --locked

# ---------- Stage 2: 最终镜像 ----------
FROM alpine:3.20

RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    iproute2 \
    bash \
    curl \
    ca-certificates

# 复制 BoringTun
COPY --from=builder /usr/local/cargo/bin/boringtun-cli /usr/local/bin/boringtun-cli

# 安装 frpc（下载预编译二进制）
ARG FRP_VERSION=0.68.1
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
        x86_64)  FARCH="amd64" ;; \
        aarch64) FARCH="arm64" ;; \
        *)       echo "Unsupported: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FARCH}.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "frp_${FRP_VERSION}_linux_${FARCH}/frpc" && \
    chmod +x /usr/local/bin/frpc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 挂载点:
#   /etc/wireguard/wgcf-profile.conf  ← wgcf 生成的 WireGuard 配置
#   /etc/frp/frpc.toml                ← frpc 配置

ENTRYPOINT ["/entrypoint.sh"]
