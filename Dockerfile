# 基础镜像
FROM alpine:3.20

# 构建参数
ARG SINGBOX_VERSION="1.11.13"
ARG WARP_VERSION="v2.0.2"
ARG TARGETARCH

# 安装依赖
RUN set -ex && \
    apk update && apk add --no-cache \
        curl ca-certificates iproute2 iptables \
        wireguard-tools openresolv tar bash net-tools && \
    rm -rf /var/cache/apk/*

# 安装 sing-box（使用官方标准包，支持多架构）
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading Sing-box version: ${SINGBOX_VERSION}" && \
    curl -fsSL -o /tmp/singbox.tar.gz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/singbox.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/sing-box && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*

# 安装 warp 优选工具
RUN set -ex && \
    curl -fsSL -o /usr/local/bin/warp \
      "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" && \
    chmod +x /usr/local/bin/warp

# 安装 wgcf
RUN curl -fsSL git.io/wgcf.sh | bash

# 工作目录和启动脚本
WORKDIR /wgcf
COPY entry.sh /entry.sh
RUN chmod +x /entry.sh

ENTRYPOINT ["/entry.sh"]
