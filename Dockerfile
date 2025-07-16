# 最终版 Dockerfile: 集成 jq, zashboard UI, 和动态 IP 优选 (arm64)
FROM alpine:3.20

# 1. 安装基础依赖, 新增 jq 用于处理 JSON
RUN apk update && \
    apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    unzip \
    jq && \
    rm -rf /var/cache/apk/*

# 2. 安装 sing-box (linux-arm64)
RUN LATEST_URL=$(curl -sL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep "browser_download_url" | grep "linux-arm64" | cut -d '"' -f 4) && \
    curl -sLo /tmp/sing-box.tar.gz "$LATEST_URL" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/ && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*

# ==================== ↓↓↓ 这里是修改的部分 ↓↓↓ ====================
# 3. 下载并固化 Clash API 的 Web UI (zashboard)
RUN mkdir -p /opt/app/ui && \
    echo "Downloading zashboard Web UI..." && \
    curl -sL "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip" -o /tmp/zashboard.zip && \
    unzip /tmp/zashboard.zip -d /opt/app/ui/ && \
    echo "UI download complete." && \
    rm -rf /tmp/zashboard.zip
# ==================== ↑↑↑ 这里是修改的部分 ↑↑↑ ====================

# 4. 拷贝所有项目文件
WORKDIR /opt/app
COPY warp-arm64 /usr/local/bin/warp
COPY entry.sh .
COPY config.json.template .

# 5. 拷贝自定义规则文件
RUN mkdir -p /etc/sing-box/rules
COPY rules/ /etc/sing-box/rules/

# 6. Final setup
RUN chmod +x /usr/local/bin/warp && \
    chmod +x entry.sh

# 7. 创建用于存放最终配置的目录
RUN mkdir -p /etc/sing-box

ENTRYPOINT ["/opt/app/entry.sh"]
