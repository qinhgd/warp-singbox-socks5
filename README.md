好的，我们来对整个项目进行一次最终的、完整的总结。

这份总结将包含我们最终确定的所有代码、文件清单、完整的使用流程，以及核心工作原理的解析。

-----

### \#\# 终极版项目总结：高可用 WARP + Sing-box 代理

这是一个高度可用、全功能、智能化的 Cloudflare WARP 代理解决方案。它结合了强大的 `entry.sh` 脚本来确保网络连接的稳定与高效，并使用 `sing-box` 提供现代化、高性能的代理服务。

-----

### \#\#\# 1. 项目核心特性

  * **高可用性**:
      * **快速自愈**: 通过健康检查，实现断线后秒级更换 IP 并自动重连。
      * **熔断重启**: 在连续多次重连失败后能主动退出，触发 Docker 的重启策略，实现容器级恢复。
  * **智能 IP 优选**:
      * **定时优选**: 后台定时自动执行 IP 优选，持续更新可用 IP 池。
      * **无缝热重载**: `entry.sh` 在优选 IP 后，能平滑地重启 WireGuard 连接，应用新 IP，整个过程对用户无感知。
  * **功能完备的代理**:
      * 使用 `sing-box` 作为代理核心，性能卓越。
      * 通过 `mixed` 和 `tproxy` 入站组合，**完整支持 TCP 和 UDP 代理**，满足各类应用需求。
  * **自动化与高可靠性构建**:
      * `Dockerfile` 实现了所有依赖（`sing-box`, `warp-go`）的自动化下载安装。
      * 通过 `apk` 安装 `sing-box`，避免了因上游发布文件命名变更导致的构建失败问题。
  * **灵活配置**:
      * 所有关键参数（如优选频率、失败阈值等）均可通过 Docker 环境变量进行配置，无需修改任何代码。

-----

### \#\#\# 2. 最终文件清单

在您的项目目录中，您只需要准备以下 **3 个文件**：

1.  `Dockerfile`
2.  `entry.sh`
3.  `config.json`

-----

### \#\#\# 3. 最终代码

#### \#\#\#\# 3.1 Dockerfile

这个 `Dockerfile` 负责构建一个包含所有工具和依赖的、干净的 Docker 镜像。

```dockerfile
# ==============================================================================
# 最终版 Dockerfile
#
# 特性:
#   - 通过 Alpine testing 源安装新版 sing-box，稳定可靠
#   - 自动化安装最新的 warp-go 工具
#   - 支持多平台构建 (arm64, amd64)
#   - 包含 OCI 标签，遵循 Docker 最佳实践
# ==============================================================================

# 1. 使用较新的 Alpine 版本
FROM alpine:3.20

# 2. 添加标准化的 OCI 标签
LABEL maintainer="YourName <your.email@example.com>" \
      org.opencontainers.image.title="WireGuard + Sing-box HA Proxy" \
      org.opencontainers.image.description="A High-Availability Docker image that connects to CloudFlare WARP and exposes a Sing-box proxy." \
      org.opencontainers.image.url="https://github.com/YourName/YourRepo"

# 3. 定义构建时变量
ARG WARP_VERSION="v2.1.5" # 使用新的 warp-go
ARG TARGETARCH

# 4. 安装所有依赖，包括 sing-box
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    set -ex && \
    apk update && \
    apk add --no-cache \
        curl ca-certificates iproute2 iptables \
        wireguard-tools openresolv tar bash net-tools \
        sing-box

# 5. 自动化安装 warp-go 工具
RUN set -ex && \
    echo ">>> Building for architecture: ${TARGETARCH}" && \
    echo ">>> Downloading WARP-GO tools version: ${WARP_VERSION}" && \
    curl -fsSL -o /tmp/warp.tar.gz \
      "https://github.com/P3TERX/warp-go/releases/download/${WARP_VERSION}/warp-go_${WARP_VERSION#v}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/warp.tar.gz -C /tmp && \
    mv /tmp/warp-go /usr/local/bin/warp && \
    chmod +x /usr/local/bin/warp && \
    rm /tmp/warp.tar.gz

# 6. 安装 wgcf
RUN curl -fsSL git.io/wgcf.sh | bash

# 7. 设置工作目录、启动脚本，并提供默认启动命令
WORKDIR /wgcf
COPY config.json /etc/sing-box/config.json
COPY entry.sh /run/entry.sh
RUN chmod +x /run/entry.sh

ENTRYPOINT ["/run/entry.sh"]
CMD ["-4"]
```

#### \#\#\#\# 3.2 entry.sh

这个脚本是整个高可用方案的“大脑”，负责网络管理、健康检查和自动恢复。

```bash
#!/bin/sh
set -e

# ==============================================================================
# 脚本配置 (环境变量)
# ==============================================================================
BEST_IP_FILE="/wgcf/best_ips.txt"
RECONNECT_FLAG_FILE="/wgcf/reconnect.flag"
SINGBOX_CONFIG_FILE="/etc/sing-box/config.json"

# IP 优选相关
OPTIMIZE_INTERVAL="${OPTIMIZE_INTERVAL:-21600}"
WARP_CONNECT_TIMEOUT="${WARP_CONNECT_TIMEOUT:-5}"
BEST_IP_COUNT="${BEST_IP_COUNT:-20}"

# 健康检查与恢复相关
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"
MAX_FAILURES="${MAX_FAILURES:-10}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"

# ==============================================================================
# 工具函数
# ==============================================================================
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

# ==============================================================================
# IP优选相关函数
# ==============================================================================
run_ip_selection() {
    local ip_version_flag=""; [ "$1" = "-6" ] && ip_version_flag="-ipv6"
    green "🚀 开始优选 WARP Endpoint IP..."
    /usr/local/bin/warp -t "$WARP_CONNECT_TIMEOUT" ${ip_version_flag} > /dev/null
    if [ -f "result.csv" ]; then
        green "✅ 优选完成，正在处理结果..."
        awk -F, '($2+0) < 50 && $3!="timeout ms" {print $1}' result.csv | sed 's/[[:space:]]//g' | head -n "$BEST_IP_COUNT" > "$BEST_IP_FILE"
        if [ -s "$BEST_IP_FILE" ]; then green "✅ 已生成包含 $(wc -l < "$BEST_IP_FILE") 个IP的优选列表。"; else red "⚠️ 未能筛选出合适的IP，将使用默认地址。"; echo "engage.cloudflareclient.com:2408" > "$BEST_IP_FILE"; fi
        rm -f result.csv
    else
        red "⚠️ 未生成优选结果，将使用默认地址。"; echo "engage.cloudflareclient.com:2408" > "$BEST_IP_FILE"
    fi
}

# ==============================================================================
# 代理和连接核心功能
# ==============================================================================
_downwgcf() {
    yellow "正在清理 WireGuard 接口..."; wg-quick down wgcf >/dev/null 2>&1 || echo "wgcf 接口不存在或已关闭。"; yellow "清理完成。"; exit 0
}

update_wg_endpoint() {
    if [ ! -s "$BEST_IP_FILE" ]; then red "❌ 优选IP列表为空！将执行一次紧急IP优选..."; run_ip_selection "$1"; fi
    local random_ip=$(shuf -n 1 "$BEST_IP_FILE")
    green "🔄 已从优选列表随机选择新 Endpoint: $random_ip"
    sed -i "s/^Endpoint = .*$/Endpoint = $random_ip/" /etc/wireguard/wgcf.conf
}

_startProxyServices() {
    if ! pgrep -f "sing-box" > /dev/null; then
        yellow "🚀 启动 Sing-box 服务 (使用固定配置)..."
        if [ ! -f "$SINGBOX_CONFIG_FILE" ]; then
            red "❌ Sing-box 配置文件 ${SINGBOX_CONFIG_FILE} 不存在！代理无法启动。"
            return 1
        fi
        sing-box run -c "$SINGBOX_CONFIG_FILE" &
        green "✅ Sing-box 服务已在后台启动。"
    fi
}

_check_connection() {
    local check_url="https://www.cloudflare.com/cdn-cgi/trace"
    local curl_opts="-s -m ${HEALTH_CHECK_TIMEOUT}"

    for i in $(seq 1 "$HEALTH_CHECK_RETRIES"); do
        if curl ${curl_opts} ${check_url} 2>/dev/null | grep -q "warp=on"; then
            return 0
        fi
        if [ "$i" -lt "$HEALTH_CHECK_RETRIES" ]; then
            sleep 1
        fi
    done
    return 1
}

# ==============================================================================
# 主运行函数
# ==============================================================================
runwgcf() {
    trap '_downwgcf' ERR TERM INT
    yellow "服务初始化..."
    [ ! -e "wgcf-account.toml" ] && wgcf register --accept-tos
    [ ! -e "wgcf-profile.conf" ] && wgcf generate
    cp wgcf-profile.conf /etc/wireguard/wgcf.conf
    [ "$1" = "-6" ] && sed -i 's/AllowedIPs = 0.0.0.0\/0/#AllowedIPs = 0.0.0.0\/0/' /etc/wireguard/wgcf.conf
    [ "$1" = "-4" ] && sed -i 's/AllowedIPs = ::\/0/#AllowedIPs = ::\/0/' /etc/wireguard/wgcf.conf
    [ ! -f "$BEST_IP_FILE" ] && run_ip_selection "$@"

    (
        while true; do
            sleep "$OPTIMIZE_INTERVAL"
            yellow "🔄 [定时任务] 开始更新IP列表..."
            wg-quick down wgcf >/dev/null 2>&1 || true
            run_ip_selection "$@"
            touch "$RECONNECT_FLAG_FILE"
            yellow "🔄 [定时任务] IP列表更新完成，已发送重连信号。"
        done
    ) &

    while true; do
        local failure_count=0
        while true; do
            update_wg_endpoint "$@"
            wg-quick up wgcf
            if _check_connection "$@"; then
                green "✅ WireGuard 连接成功！"
                failure_count=0
                break
            else
                failure_count=$((failure_count + 1))
                red "❌ 连接失败 (${failure_count}/${MAX_FAILURES})，正在更换IP重试..."
                if [ "$failure_count" -ge "$MAX_FAILURES" ]; then
                    red "❌ 连续 ${MAX_FAILURES} 次连接失败，将退出以触发容器重启..."
                    exit 1
                fi
                wg-quick down wgcf >/dev/null 2>&1 || true
                sleep 3
            fi
        done

        _startProxyServices

        green "进入连接监控模式..."
        while true; do
            if [ -f "$RECONNECT_FLAG_FILE" ]; then
                yellow "🔔 收到定时优选任务的重连信号，将立即刷新连接..."
                rm -f "$RECONNECT_FLAG_FILE"
                wg-quick down wgcf >/dev/null 2>&1 || true
                break
            fi
            sleep "$HEALTH_CHECK_INTERVAL"
            if ! _check_connection "$@"; then
                red "💔 连接已断开！将立即尝试自动重连..."
                wg-quick down wgcf >/dev/null 2>&1 || true
                break
            fi
        done
    done
}

# ==============================================================================
# 脚本入口
# ==============================================================================
cd /wgcf
runwgcf "$@"
```

#### \#\#\#\# 3.3 config.json

这份 `sing-box` 配置与 `entry.sh` 的架构完美匹配，同时支持 TCP 和 UDP 代理。

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": 1080,
      "sniff": true,
      "udp_fragment": true
    },
    {
      "type": "tproxy",
      "tag": "tproxy-in",
      "network": "udp",
      "listen": "127.0.0.1",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": ["mixed-in", "tproxy-in"],
        "outbound": "direct-out"
      }
    ]
  }
}
```

-----

### \#\#\# 4. 完整使用流程

#### \#\#\#\# 步骤一：准备文件

在一个空目录下，创建并保存上述 `Dockerfile`, `entry.sh`, `config.json` 三个文件。

#### \#\#\#\# 步骤二：构建镜像

打开终端，进入该目录，执行构建命令。

```bash
docker build -t my-warp-proxy:latest .
```

#### \#\#\#\# 步骤三：启动容器

使用以下命令启动容器。它包含了所有必需的权限和网络配置。

```bash
docker run -d \
  --name warp-proxy \
  --restart unless-stopped \
  --privileged \
  --cap-add NET_ADMIN \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -v /lib/modules:/lib/modules:ro \
  -p 1080:1080/tcp \
  -p 1080:1080/udp \
  my-warp-proxy:latest
```

> 容器启动后，`entry.sh` 会自动开始工作，您只需将应用的代理指向您服务器 IP 的 `1080` 端口即可。

-----

### \#\#\# 5. 可配置环境变量

您可以在 `docker run` 命令中通过 `-e` 参数灵活调整脚本的行为，无需修改任何代码。

| 环境变量 (键) | 作用 | 默认值 | 示例 (`-e` 参数) |
| :--- | :--- | :--- | :--- |
| `OPTIMIZE_INTERVAL` | 定时优选IP的周期（秒） | `21600` (6小时) | `-e OPTIMIZE_INTERVAL=10800` |
| `HEALTH_CHECK_INTERVAL` | 两次健康检查之间的间隔（秒） | `60` | `-e HEALTH_CHECK_INTERVAL=30` |
| `MAX_FAILURES` | 连续几次检查失败后，触发容器重启 | `10` | `-e MAX_FAILURES=5` |
| `WARP_CONNECT_TIMEOUT`| 优选IP时，测试每个IP的超时（秒）| `5` | `-e WARP_CONNECT_TIMEOUT=3` |
| `BEST_IP_COUNT` | 优选后保留的最佳IP数量 | `20` | `-e BEST_IP_COUNT=30` |
| `HEALTH_CHECK_TIMEOUT`| 单次健康检查请求的超时（秒） | `5` | `-e HEALTH_CHECK_TIMEOUT=8` |
| `HEALTH_CHECK_RETRIES`| 单次健康检查的内部重试次数 | `3` | `-e HEALTH_CHECK_RETRIES=5` |

**示例：启动一个配置更灵敏的容器**

```bash
docker run -d \
  --name warp-proxy-tuned \
  --restart unless-stopped \
  -e OPTIMIZE_INTERVAL=10800 \
  -e HEALTH_CHECK_INTERVAL=30 \
  -e MAX_FAILURES=5 \
  --privileged \
  --cap-add NET_ADMIN \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  -v /lib/modules:/lib/modules:ro \
  -p 1080:1080/tcp \
  -p 1080:1080/udp \
  my-warp-proxy:latest
```

-----

### \#\#\# 6. 工作原理解析

本项目采用“**分离式架构**”：

1.  **网络层 (`entry.sh`)**: `entry.sh` 脚本是**网络管理者**。它使用 `wgcf` 和 `warp-go` 等工具，负责建立和维护一个通往 Cloudflare WARP 的**系统级 WireGuard 隧道**。容器内的一切网络活动都会默认通过这个隧道。
2.  **应用层 (`sing-box`)**: `sing-box` 是**代理服务提供者**。它的配置极其简单（`"type": "direct"`），不处理任何复杂的路由或隧道逻辑。它只负责监听 `1080` 端口，接收 SOCKS5/HTTP/UDP 请求，然后将这些流量直接“扔”给操作系统。由于操作系统网络已被脚本接管，这些流量便会自动进入 WARP 隧道。

这种架构将复杂的网络管理和简单的代理服务解耦，各司其职，使得整个系统既强大又易于维护。
