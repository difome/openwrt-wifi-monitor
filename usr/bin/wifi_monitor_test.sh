#!/bin/sh
# /usr/bin/wifi_monitor_test.sh

BOT_TOKEN=$(uci -q get wifi_monitor.settings.bot_token)
CHAT_ID=$(uci -q get wifi_monitor.settings.chat_id)
LOG_FILE="/tmp/wifi_monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "ТЕСТ ОШИБКА: не заданы bot_token или chat_id"
    exit 1
fi

IP=$(uci -q get network.lan.ipaddr || echo "?")
MSG="🔔 <b>WiFi Monitor: тест</b>
Роутер: <code>${IP}</code>
Время: $(date '+%Y-%m-%d %H:%M:%S')
Всё работает ✅"

RESP=$(curl -s -m 10 -X POST \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=${MSG}" 2>&1)

if echo "$RESP" | grep -q '"ok":true'; then
    log "ТЕСТ: успешно отправлено"
    exit 0
else
    ERR=$(echo "$RESP" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
    log "ТЕСТ ОШИБКА: ${ERR:-нет ответа}"
    exit 1
fi
