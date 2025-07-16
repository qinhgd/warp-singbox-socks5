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

inject_private_key() {
    PRIVATE_KEY=$(grep PrivateKey /etc/wireguard/wgcf.conf | awk '{print $3}')
    IPV4=$(grep Address /etc/wireguard/wgcf.conf | grep -v ":" | awk '{print $3}' | cut -d '/' -f1)
    IPV6=$(grep Address /etc/wireguard/wgcf.conf | grep ":" | awk '{print $3}' | cut -d '/' -f1)
    sed "s|__PRIVATE_KEY__|$PRIVATE_KEY|g; s|__IPV4__|$IPV4/32|g; s|__IPV6__|$IPV6/128|g" singbox.json.template > "$CONFIG_JSON"
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
    fi
}

run() {
    trap 'wg-quick down wgcf >/dev/null 2>&1; exit 0' TERM INT

    [ ! -e wgcf-account.toml ] && wgcf register --accept-tos
    [ ! -e wgcf-profile.conf ] && wgcf generate
    cp wgcf-profile.conf /etc/wireguard/wgcf.conf
    [ ! -f "$BEST_IP_FILE" ] && run_ip_selection
    inject_private_key

    (
        while true; do
            sleep "$OPTIMIZE_INTERVAL"
            wg-quick down wgcf >/dev/null 2>&1 || true
            run_ip_selection
            touch "$RECONNECT_FLAG_FILE"
        done
    ) &

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
            [ -f "$RECONNECT_FLAG_FILE" ] && rm -f "$RECONNECT_FLAG_FILE" && wg-quick down wgcf && break
            sleep "$HEALTH_CHECK_INTERVAL"
            _check_connection || { wg-quick down wgcf && break; }
        done
    done
}

cd /wgcf
run
