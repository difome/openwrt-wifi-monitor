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
        log "OK → $(echo "$msg" | sed -e 's/<[^>]*>//g' | head -1)"
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
DEBOUNCE_TIME=$(uci -q get wifi_monitor.settings.timeout || echo 20)

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "ОШИБКА: bot_token или chat_id не заданы"
    exit 1
fi

PENDING_GONE_DIR="/tmp/wifi_pending_gone"
mkdir -p "$PENDING_GONE_DIR"

log "СТАРТ: демон wifi_monitor запущен (с защитой от спама, таймаут: ${DEBOUNCE_TIME}с)"

# Функция для получения списка уникальных MAC с их основным интерфейсом
# Возвращает строки формата "MAC IFACE" (если MAC на нескольких - берем первый)
scan_clients() {
    get_clients | sort -k1,1 -u
}

while true; do
    # 1. Делаем ЕДИНЫЙ снимок системы на этот цикл
    CURRENT_LIST=$(scan_clients)
    CURRENT_MACS=$(echo "$CURRENT_LIST" | awk '{print $1}')

    # Если файла состояния нет - инициализируем и спим
    if [ ! -f "$STATE_FILE" ]; then
        echo "$CURRENT_LIST" > "$STATE_FILE"
        sleep "$DEBOUNCE_TIME"
        continue
    fi

    PREVIOUS_LIST=$(cat "$STATE_FILE")
    PREVIOUS_MACS=$(echo "$PREVIOUS_LIST" | awk '{print $1}')

    # 2. Обработка ПОДКЛЮЧЕНИЙ
    # Ищем MAC, которых нет в PREVIOUS_MACS, но есть в CURRENT_MACS
    echo "$CURRENT_LIST" | while read mac iface; do
        [ -z "$mac" ] && continue
        if ! echo "$PREVIOUS_MACS" | grep -qi "$mac"; then
            # Если он был в очереди на уход - просто "вычеркиваем" его
            if [ -f "$PENDING_GONE_DIR/$mac" ]; then
                rm -f "$PENDING_GONE_DIR/$mac"
                log "ВОЗВРАТ: $mac (роуминг или глюк пресечен)"
            else
                h=$(get_hostname "$mac")
                ip=$(get_ip "$mac")
                ip_str=""
                [ -n "$ip" ] && ip_str=$(printf '\nIP: <code>%s</code>' "$ip")
                msg=$(printf '<blockquote><b>✅ Подключился</b>\nMAC: <code>%s</code>\nУстройство: %s%s\nИнтерфейс: <code>%s</code></blockquote>' "$mac" "$h" "$ip_str" "$iface")
                send_tg "$msg"
                log "ПОДКЛЮЧЕНИЕ: $mac ($h) на $iface"
            fi
        fi
    done

    # 3. Обработка ОТКЛЮЧЕНИЙ (постановка в очередь)
    # Ищем MAC, которые есть в PREVIOUS_MACS, но исчезли из CURRENT_MACS
    echo "$PREVIOUS_LIST" | while read mac iface; do
        [ -z "$mac" ] && continue
        if ! echo "$CURRENT_MACS" | grep -qi "$mac"; then
            if [ ! -f "$PENDING_GONE_DIR/$mac" ]; then
                echo "$(date +%s) $iface" > "$PENDING_GONE_DIR/$mac"
                log "ЗАМЕЧЕН УХОД: $mac, ждем ${DEBOUNCE_TIME}с..."
            fi
        fi
    done

    # 4. Проверка очереди (подтверждение ухода)
    NOW=$(date +%s)
    ls "$PENDING_GONE_DIR" 2>/dev/null | while read mac; do
        [ -z "$mac" ] && continue
        f="$PENDING_GONE_DIR/$mac"
        read start_ts p_iface < "$f"

        # Если время вышло
        if [ $((NOW - start_ts)) -ge "$DEBOUNCE_TIME" ]; then
            # Проверяем по свежему снимку - его все еще нет?
            if ! echo "$CURRENT_MACS" | grep -qi "$mac"; then
                h=$(get_hostname "$mac")
                ip=$(get_ip "$mac")
                ip_str=""
                [ -n "$ip" ] && ip_str=$(printf '\nIP: <code>%s</code>' "$ip")
                msg=$(printf '<blockquote><b>❌ Отключился</b>\nMAC: <code>%s</code>\nУстройство: %s%s\nИнтерфейс: <code>%s</code></blockquote>' "$mac" "$h" "$ip_str" "$p_iface")
                send_tg "$msg"
                log "ОТКЛЮЧЕНИЕ ПОДТВЕРЖДЕНО: $mac ($h)"
            fi
            rm -f "$f"
        fi
    done

    # Обновляем состояние на основе текущего снимка
    echo "$CURRENT_LIST" > "$STATE_FILE"
    sleep 5
done
