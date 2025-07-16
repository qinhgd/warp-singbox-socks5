# ==============================================================================
# 终极版 Dockerfile v4
#
# 特性:
#   - 使用了您提供的、经过验证的正确下载链接格式，解决了下载失败问题。
#   - 完全自动化，无需本地文件。
#   - 支持多平台构建 (arm64, amd64)。
#   - 遵循 Docker 最佳实践。
# ==============================================================================

# 1. 使用较新的 Alpine 版本
FROM alpine:3.20

# 2. 添加标准化的 OCI 标签，让镜像信息更丰富、更专业
LABEL maintainer="YourName <your.email@example.com>" \
      org.opencontainers.image.title="WireGuard + Sing-box HA Proxy" \
      org.opencontainers.image.description="A High-Availability Docker image that connects to CloudFlare WARP and exposes a Sing-box proxy." \
      org.opencontainers.image.authors="YourName <your.email@example.com>" \
      org.opencontainers.image.vendor="YourProject" \
      org.opencontainers.image.version="4.1.0" \
      org.opencontainers.image.url="https://hub.docker.com/r/yourname/your-repo" \
      org.opencontainers.image.source="https://github.com/YourName/YourRepo"

# 3. 定义构建时变量
ARG SINGBOX_VERSION="1.9.1"
ARG WARP_VERSION="v2.0.2"
ARG TARGETARCH

# 4. 下载并安装 sing-box (已使用您验证过的正确链接格式)
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading Sing-box version: ${SINGBOX_VERSION}" && \
    # ✨ 最终修正：根据您提供的链接，已移除所有不正确的后缀，使用官方的确切命名格式
    curl -fsSL -o /tmp/singbox.tar.gz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/singbox.tar.gz -C /tmp && \
    # 使用通配符(*)，使命令对上游目录名的微小变化不敏感
    mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*

# 5. 自动化安装 warp 工具
RUN set -ex && \
    echo ">>> Downloading WARP tools version: ${WARP_VERSION}" && \
    curl -fsSL -o /usr/local/bin/warp \
      "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/warp

# 6. 安装 wgcf
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. 设置工作目录和启动脚本
WORKDIR /wgcf
COPY entry.sh /run/entry.sh
RUN chmod +x /run/entry.sh

ENTRYPOINT ["/run/entry.sh"]

# 提供一个默认命令，简化启动
CMD ["-4"]
