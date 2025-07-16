# ==============================================================================
# 终极优化版 Dockerfile
# 特性:
#   - 完全自动化，无需本地文件
#   - 支持多平台构建 (arm64, amd64)
#   - 遵循 Docker 最佳实践
# ==============================================================================

# 1. 使用更新的基础镜像，以获得最新的安全补丁和软件包
FROM alpine:3.20

# 2. 使用 ARG 定义构建时变量，方便在构建命令中覆盖版本
ARG SINGBOX_VERSION="1.9.1" # 使用一个较新的稳定版作为默认值
ARG WARP_VERSION="v2.0.2"
# 声明 TARGETARCH，它的值将由 Docker Buildx 在构建时自动传入 (如 arm64, amd64)
ARG TARGETARCH

# 3. 安装基础依赖
#    - 使用 set -ex 确保命令失败时立即退出
#    - 将 apk 命令合并，减少层数
RUN set -ex && \
    apk update && \
    apk add --no-cache \
        curl ca-certificates iproute2 iptables \
        wireguard-tools openresolv tar bash net-tools

# 4. 下载并安装 sing-box (自动化、多平台、更健壮)
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading Sing-box version: ${SINGBOX_VERSION}" && \
    curl -fsSL -o /tmp/singbox.tar.gz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/singbox.tar.gz -C /tmp && \
    # 使用通配符(*)，使命令对上游目录名的微小变化不敏感
    mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*

# 5. 下载并安装 warp 优选工具 (自动化、多平台)
RUN set -ex && \
    echo ">>> Downloading WARP tools version: ${WARP_VERSION}" && \
    curl -fsSL -o /usr/local/bin/warp \
      "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/warp

# 6. 安装 wgcf (保持不变，这种方式已经很高效)
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. 设置工作目录和启动脚本 (保持不变，这是标准做法)
WORKDIR /wgcf
COPY entry.sh /entry.sh
RUN chmod +x /entry.sh

ENTRYPOINT ["/entry.sh"]
