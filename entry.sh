#!/bin/bash
set -e

BEST_IP_FILE="/wgcf/best_ips.txt"
RECONNECT_FLAG_FILE="/wgcf/reconnect.flag"
CONFIG_JSON="/wgcf/singbox.json"

OPTIMIZE_INTERVAL="${OPTIMIZE_INTERVAL:-21600}"
WARP_CONNECT_TIMEOUT="${WARP_CONNECT_TIMEOUT:-5}"
BEST_IP_COUNT="${BEST_IP_COUNT:-20}"
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-60}"
MAX_FAILURES="${MAX_FAILURES:-10}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-5}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"

color() { echo -e "\033[$1m\033[01m$2\033[0m"; }
green() { color 32 "$1"; }
yellow() { color 33 "$1"; }
red() { color 31 "$1"; }

run_ip_selection() {
    /usr/local/bin/warp -t "$WARP_CONNECT_TIMEOUT" > /dev/null
    if [ -f "result.csv" ]; then
        awk -F, '($2+0)<50 && $3!="timeout ms"{print $1}' result.csv | sed 's/[[:space:]]//g' | head -n "$BEST_IP_COUNT" > "$BEST_IP_FILE"
        [ ! -s "$BEST_IP_FILE" ] && echo "engage.cloudflareclient.com:2408" > "$BEST_IP_FILE"
        rm -f result.csv
    else
        echo "engage.cloudflareclient.com:2408" > "$BEST_IP_FILE"
    fi
}

_check_connection() {
    for i in $(seq 1 "$HEALTH_CHECK_RETRIES"); do
        if curl -s -m "$HEALTH_CHECK_TIMEOUT" https://www.cloudflare.com/cdn-cgi/trace | grep -q "warp=on"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

update_wg_endpoint() {
    local endpoint=$(shuf -n 1 "$BEST_IP_FILE")
    sed -i "s/^Endpoint = .*/Endpoint = $endpoint/" /etc/wireguard/wgcf.conf
}

_startProxy() {
    if ! pgrep -f "sing-box" > /dev/null; then
        /usr/local/bin/sing-box run -c "$CONFIG_JSON" &
        green "[*] sing-box started"
    fi
}

run() {
    trap 'wg-quick down wgcf >/dev/null 2>&1; exit 0' TERM INT

    # Warp 账号注册和生成配置
    [ ! -e wgcf-account.toml ] && wgcf register --accept-tos
    [ ! -e wgcf-profile.conf ] && wgcf generate
    cp wgcf-profile.conf /etc/wireguard/wgcf.conf

    # 生成 IP 优选列表
    [ ! -f "$BEST_IP_FILE" ] && run_ip_selection

    # 定时优化 IP
    (
        while true; do
            sleep "$OPTIMIZE_INTERVAL"
            wg-quick down wgcf >/dev/null 2>&1 || true
            run_ip_selection
            touch "$RECONNECT_FLAG_FILE"
        done
    ) &

    # 主循环
    while true; do
        local fail=0
        while true; do
            update_wg_endpoint
            wg-quick up wgcf
            if _check_connection; then break; fi
            wg-quick down wgcf >/dev/null 2>&1 || true
            ((fail++))
            [ "$fail" -ge "$MAX_FAILURES" ] && exit 1
            sleep 3
        done

        _startProxy
        while true; do
            if [ -f "$RECONNECT_FLAG_FILE" ]; then
                rm -f "$RECONNECT_FLAG_FILE"
                wg-quick down wgcf
                break
            fi
            sleep "$HEALTH_CHECK_INTERVAL"
            _check_connection || { wg-quick down wgcf && break; }
        done
    done
}

cd /wgcf
run
