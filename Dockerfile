# ==============================================================================
# 定制版 Dockerfile
#
# 基于您的要求:
#   - 代理核心 (sing-box) 和 wgcf 从网络自动安装。
#   - WARP 工具 (warp-arm64) 由您手动提供并复制到镜像中。
# ==============================================================================

# 1. 使用较新的 Alpine 版本以获得安全更新
FROM alpine:3.20

# 2. 添加标准化的 OCI 标签，让镜像信息更专业
LABEL maintainer="YourName <your.email@example.com>" \
      org.opencontainers.image.title="WireGuard + Sing-box HA Proxy (Custom Build)" \
      org.opencontainers.image.description="A custom-built, High-Availability Docker image that connects to CloudFlare WARP and exposes a Sing-box proxy." \
      org.opencontainers.image.url="https://github.com/YourName/YourRepo"

# 3. 启用 testing 源，以便安装较新版本的 sing-box
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

# 4. 安装基础依赖和 Sing-box
RUN set -ex && \
    apk update && \
    # 直接通过 apk 安装 sing-box，无需手动下载
    apk add --no-cache \
        curl ca-certificates iproute2 net-tools iptables \
        wireguard-tools openresolv tar bash \
        sing-box

# 5. (按您要求) WARP 工具安装 (从本地 arm64 文件)
#    请确保构建目录下存在名为 warp-arm64 的文件
COPY warp-arm64 /usr/local/bin/warp
RUN chmod +x /usr/local/bin/warp

# 6. WGCF 安装 (从网络)
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. 设置工作目录、启动脚本，并提供默认启动命令
WORKDIR /wgcf
COPY entry.sh /run/entry.sh
RUN chmod +x /run/entry.sh
RUN mkdir -p /etc/sing-box
COPY config.json /etc/sing-box/config.json
ENTRYPOINT ["/run/entry.sh"]

# 默认以 IPv4 模式启动
CMD ["-4"]
