# 最终版 Dockerfile: arm64 专用, 全自动下载依赖, 已修复路径问题
FROM alpine:3.18

# --- 构建参数 (默认使用一个已知的稳定版本，可在构建时覆盖) ---
ARG SINGBOX_VERSION="1.11.15"
ARG WARP_VERSION="v2.0.2"
ARG TARGETARCH="arm64"

# --- 安装基础依赖 ---
RUN apk update -f \
  && apk --no-cache add -f \
    curl ca-certificates unzip \
    iproute2 net-tools iptables \
    wireguard-tools openresolv \
  && rm -rf /var/cache/apk/*

# --- Sing-box 安装 (从官方 Release 自动下载) ---
RUN echo ">>> Downloading Sing-box version: ${SINGBOX_VERSION}" \
    && set -ex \
    && curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-${TARGETARCH}.tar.gz" -o "/tmp/sing-box.tar.gz" \
    && tar -xzf /tmp/sing-box.tar.gz -C /tmp \
    # ✨ FIX: 使用通配符 (*) 查找解压后的目录，更具鲁棒性
    && mv /tmp/sing-box-*/sing-box /usr/local/bin/ \
    && chmod +x /usr/local/bin/sing-box \
    && rm -rf /tmp/*

# --- WARP 工具安装 (从官方 Release 自动下载) ---
RUN set -ex \
    && curl -fsSL "https://github.com/P3TERX/warp.sh/releases/download/${WARP_VERSION}/warp-linux-${TARGETARCH}" -o "/usr/local/bin/warp" \
    && chmod +x /usr/local/bin/warp

# --- WGCF 安装 (从网络) ---
RUN curl -fsSL git.io/wgcf.sh | bash

# --- Sing-box 配置 ---
RUN mkdir -p /etc/sing-box
COPY config.json /etc/sing-box/config.json

# --- 最终设置 ---
WORKDIR /wgcf

COPY entry.sh /entry.sh
RUN chmod +x /entry.sh

ENTRYPOINT ["/entry.sh"]
