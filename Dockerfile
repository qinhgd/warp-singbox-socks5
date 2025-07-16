# ==============================================================================
# 终极版 Dockerfile v3
#
# 特性:
#   - 通过 Alpine testing 源安装新版 sing-box，稳定可靠
#   - 完全自动化，无需本地文件
#   - 支持多平台构建 (arm64, amd64)
#   - 包含 OCI 标签，遵循 Docker 最佳实践
# ==============================================================================

# 1. 使用较新的 Alpine 版本
FROM alpine:3.20

# 2. 添加标准化的 OCI 标签，让镜像信息更丰富、更专业
#    请根据您的实际情况修改这些值
LABEL maintainer="YourName <your.email@example.com>" \
      org.opencontainers.image.title="WireGuard + Sing-box HA Proxy" \
      org.opencontainers.image.description="A High-Availability Docker image that connects to CloudFlare WARP and exposes a Sing-box proxy." \
      org.opencontainers.image.authors="YourName <your.email@example.com>" \
      org.opencontainers.image.vendor="YourProject" \
      org.opencontainers.image.version="3.0.0" \
      org.opencontainers.image.url="https://hub.docker.com/r/yourname/your-repo" \
      org.opencontainers.image.source="https://github.com/YourName/YourRepo"

# 3. 定义构建时变量，保留对 warp 版本的控制和对多平台的支持
ARG WARP_VERSION="v2.0.2"
ARG TARGETARCH

# 4. 核心改进：启用 testing 源并使用 apk 安装 sing-box
#    这大大简化了 Dockerfile，同时能获取到较新版本的 sing-box
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    set -ex && \
    apk update && \
    # 直接通过 apk 安装，不再需要手动下载、解压、移动
    apk add --no-cache \
        curl ca-certificates iproute2 iptables \
        wireguard-tools openresolv tar bash net-tools \
        sing-box

# 5. 保留自动化安装 warp 工具
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading WARP tools version: ${WARP_VERSION}" && \
    curl -fsSL -o /usr/local/bin/warp \
      "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/warp

# 6. 安装 wgcf
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. 设置工作目录、启动脚本，并提供默认启动命令
WORKDIR /wgcf
COPY entry.sh /run/entry.sh
RUN chmod +x /run/entry.sh

ENTRYPOINT ["/run/entry.sh"]

# 容器启动时若不指定参数，则默认使用 IPv4 模式
CMD ["-4"]
