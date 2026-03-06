#!/bin/sh
# /usr/bin/wifi_monitor.sh — procd демон

STATE_FILE="/tmp/wifi_clients.state"
LOG_FILE="/tmp/wifi_monitor.log"
MAX_LOG_LINES=200

log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $1" >> "$LOG_FILE"
    local lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt "$MAX_LOG_LINES" ]; then
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

send_tg() {
    local msg="$1"
    local resp
    resp=$(curl -s -m 10 -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=${msg}" 2>&1)
    if echo "$resp" | grep -q '"ok":true'; then
        log "OK → $(echo "$msg" | head -1)"
    else
        local err=$(echo "$resp" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
        log "ОШИБКА TG: ${err:-нет ответа}"
    fi
}

get_clients() {
    for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
        iw dev "$iface" station dump 2>/dev/null \
            | grep "^Station" \
            | awk -v iface="$iface" '{print $2, iface}'
    done
}

get_hostname() {
    local mac=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local h=$(awk -v m="$mac" 'tolower($2)==m{print $4; exit}' /tmp/dhcp.leases 2>/dev/null)
    [ -z "$h" ] || [ "$h" = "*" ] && h="неизвестно"
    echo "$h"
}

get_ip() {
    local mac=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    awk -v m="$mac" 'tolower($2)==m{print $3; exit}' /tmp/dhcp.leases 2>/dev/null
}

BOT_TOKEN=$(uci -q get wifi_monitor.settings.bot_token)
CHAT_ID=$(uci -q get wifi_monitor.settings.chat_id)

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "ОШИБКА: bot_token или chat_id не заданы"
    exit 1
fi

log "СТАРТ: демон wifi_monitor запущен"

while true; do
    CURRENT=$(get_clients | sort)

    if [ ! -f "$STATE_FILE" ]; then
        echo "$CURRENT" > "$STATE_FILE"
        sleep 5
        continue
    fi

    PREVIOUS=$(cat "$STATE_FILE")

    echo "$CURRENT" | while read mac iface; do
        [ -z "$mac" ] && continue
        if ! echo "$PREVIOUS" | grep -q "^${mac} "; then
            h=$(get_hostname "$mac")
            ip=$(get_ip "$mac")
            ip_str=""
            [ -n "$ip" ] && ip_str=$(printf '\nIP: <code>%s</code>' "$ip")
            msg=$(printf '<blockquote><b>✅ Подключился</b>\nMAC: <code>%s</code>\nУстройство: %s%s\nИнтерфейс: <code>%s</code></blockquote>' "$mac" "$h" "$ip_str" "$iface")
            send_tg "$msg"
            log "ПОДКЛЮЧЕНИЕ: $mac ($h) на $iface"
        fi
    done

    echo "$PREVIOUS" | while read mac iface; do
        [ -z "$mac" ] && continue
        if ! echo "$CURRENT" | grep -q "^${mac} "; then
            h=$(get_hostname "$mac")
            ip=$(get_ip "$mac")
            ip_str=""
            [ -n "$ip" ] && ip_str=$(printf '\nIP: <code>%s</code>' "$ip")
            msg=$(printf '<blockquote><b>❌ Отключился</b>\nMAC: <code>%s</code>\nУстройство: %s%s\nИнтерфейс: <code>%s</code></blockquote>' "$mac" "$h" "$ip_str" "$iface")
            send_tg "$msg"
            log "ОТКЛЮЧЕНИЕ: $mac ($h) на $iface"
        fi
    done

    echo "$CURRENT" > "$STATE_FILE"
    sleep 2
done
