# --- Builder Stage ---
# This stage downloads and extracts frp.
# 此阶段下载并解压 frp。
FROM alpine:latest AS builder

# Arguments for frp version and architecture
# frp 版本和架构的参数
ARG FRP_VERSION=0.48.0 # 您可以按需更改此版本 (You can change this version as needed)
ARG FRP_ARCH_SUFFIX=amd64 # 根据需要更改架构，例如 arm64 (Change architecture as needed, e.g., arm64)
ARG FRP_FOLDER_NAME="frp_${FRP_VERSION}_linux_${FRP_ARCH_SUFFIX}"
ARG FRP_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_FOLDER_NAME}.tar.gz"

# Install build dependencies
# 安装构建依赖
RUN apk add --no-cache wget tar ca-certificates

WORKDIR /tmp/frp_build

# Download and extract frpc binary
# 下载并解压 frpc 二进制文件
RUN set -ex \
    && wget -O frp.tar.gz "${FRP_DOWNLOAD_URL}" \
    && tar zxf frp.tar.gz \
    # Ensure the frpc binary is directly moved and made executable
    # 确保 frpc 二进制文件被直接移动并赋予执行权限
    && mv "${FRP_FOLDER_NAME}/frpc" /usr/local/bin/frpc_staged \
    && chmod +x /usr/local/bin/frpc_staged

# --- Final Stage ---
# This stage creates the final, small runtime image.
# 此阶段创建最终的小型运行时镜像。
FROM alpine:latest

LABEL maintainer="chuwoo <chuwooem@gmail.com>" 
# 可以替换为您的邮箱 (You can replace this with your email)

# Install runtime dependencies, including wget for the entrypoint script
# 安装运行时依赖，包括用于入口点脚本的 wget
RUN apk add --no-cache ca-certificates wget

# Create a non-root user and group for running frpc
# 为运行 frpc 创建一个非 root 用户和组
RUN addgroup -S frpuser && adduser -S -G frpuser frpuser

# Copy the default frpc.ini into the image
# 将默认的 frpc.ini 文件复制到镜像中
# 假设 default.frpc.ini 文件与 Dockerfile 在同一目录
# Assume default.frpc.ini is in the same directory as the Dockerfile
COPY frpc.ini /etc/default.frpc.ini
# Ensure correct ownership and permissions for the default config
# 确保默认配置文件的正确所有权和权限
RUN chown frpuser:frpuser /etc/default.frpc.ini && chmod 644 /etc/default.frpc.ini

# Set the working directory
# 设置工作目录
RUN mkdir -p /var/fsr && chown frpuser:frpuser /var/fsr
WORKDIR /var/fsr

# Copy frpc binary from the builder stage
# 从构建器阶段复制 frpc 二进制文件
COPY --from=builder --chown=frpuser:frpuser /usr/local/bin/frpc_staged ./frpc

# Copy the entrypoint script into the image
# 将入口点脚本复制到镜像中
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
# Ensure the script is executable and owned by frpuser
# 确保脚本可执行并由 frpuser 拥有
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chown frpuser:frpuser /usr/local/bin/entrypoint.sh

# Switch to the non-root user
# 切换到非 root 用户
USER frpuser

# Set the entrypoint to our custom script
# 将入口点设置为我们的自定义脚本
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Default command/arguments for frpc (these will be passed to entrypoint.sh as $@)
# frpc 的默认命令/参数 (这些将作为 $@ 传递给 entrypoint.sh)
# The path /var/fsr/frpc.ini here is what entrypoint.sh will use as TARGET_CONFIG_FINAL_PATH
# 这里的路径 /var/fsr/frpc.ini 是 entrypoint.sh 将用作 TARGET_CONFIG_FINAL_PATH 的路径
CMD ["-c", "/var/fsr/frpc.ini"]
