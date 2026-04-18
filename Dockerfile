ARG BASE_IMAGE=ubuntu:22.04

FROM ${BASE_IMAGE}

ARG WARP_VERSION
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="warp-global"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

# 安装依赖：nftables 用于 NAT，其余为 WARP 客户端所需
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc nftables && \
    # 添加 Cloudflare WARP 官方源并安装
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && \
    apt-get autoremove -y && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    # 创建 warp 用户并赋予 sudo 权限
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

# 自动接受 Cloudflare WARP 服务条款
RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV WARP_SLEEP=2
ENV WARP_LICENSE_KEY=
ENV REGISTER_WHEN_MDM_EXISTS=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
