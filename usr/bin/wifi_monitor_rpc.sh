#!/bin/sh
# /usr/bin/wifi_monitor_rpc.sh
# Вызывается через rpcd. Первый аргумент - команда.

CMD="$1"
LOG_FILE="/tmp/wifi_monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

service_restart() {
    rm -f /tmp/wifi_clients.state
    /etc/init.d/wifi_monitor restart 2>/dev/null
}

service_stop() {
    /etc/init.d/wifi_monitor stop 2>/dev/null
    rm -f /tmp/wifi_clients.state
}

case "$CMD" in
    save)
        # Аргументы: save <enabled> <bot_token> <chat_id>
        ENABLED="$2"
        BOT_TOKEN="$3"
        CHAT_ID="$4"

        uci set wifi_monitor.settings.enabled="$ENABLED"
        uci set wifi_monitor.settings.bot_token="$BOT_TOKEN"
        uci set wifi_monitor.settings.chat_id="$CHAT_ID"
        uci commit wifi_monitor

        if [ "$ENABLED" = "1" ]; then
            service_restart
            log "НАСТРОЙКИ: мониторинг включён"
        else
            service_stop
            log "НАСТРОЙКИ: мониторинг выключен"
        fi
        echo '{"result":"ok"}'
        ;;

    test)
        BOT_TOKEN=$(uci -q get wifi_monitor.settings.bot_token)
        CHAT_ID=$(uci -q get wifi_monitor.settings.chat_id)
        if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
            log "ТЕСТ ОШИБКА: не заданы bot_token или chat_id"
            echo '{"result":"error","msg":"bot_token или chat_id не заданы"}'
            exit 0
        fi
        IP=$(uci -q get network.lan.ipaddr || echo "?")
        MSG="🔔 WiFi Monitor тест
Роутер: ${IP}
Время: $(date '+%Y-%m-%d %H:%M:%S')
Всё работает ✅"
        RESP=$(curl -s -m 10 -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            --data-urlencode "text=${MSG}" 2>&1)
        if echo "$RESP" | grep -q '"ok":true'; then
            log "ТЕСТ: успешно отправлено"
            echo '{"result":"ok"}'
        else
            ERR=$(echo "$RESP" | grep -o '"description":"[^"]*"' | cut -d'"' -f4)
            log "ТЕСТ ОШИБКА: ${ERR:-нет ответа}"
            echo "{\"result\":\"error\",\"msg\":\"${ERR:-нет ответа от TG}\"}"
        fi
        ;;

    clear_log)
        > "$LOG_FILE"
        echo '{"result":"ok"}'
        ;;

    clients)
        # Возвращает JSON массив текущих клиентов МГНОВЕННО
        printf '{"clients":['
        iw dev 2>/dev/null | awk '/Interface/{print $2}' | while read iface; do
            iw dev "$iface" station dump 2>/dev/null | grep "^Station" | awk -v i="$iface" '{print $2, i}'
        done | awk -v first=1 '
            BEGIN {
                while ((getline < "/tmp/dhcp.leases") > 0) {
                    leases[tolower($2)] = $3 "\t" $4
                }
            }
            {
                mac = tolower($1); iface = $2
                if (mac in leases) {
                    split(leases[mac], parts, "\t")
                    ip = parts[1]; host = parts[2]
                } else {
                    ip = ""; host = ""
                }
                if (host == "" || host == "*") host = "неизвестно"
                if (first == 1) first = 0; else printf ","
                printf "{\"mac\":\"%s\",\"hostname\":\"%s\",\"ip\":\"%s\",\"iface\":\"%s\"}", $1, host, ip, iface
            }
        '
        printf ']}'
        ;;

    log)
        # Мгновенно генерирует валидный JSON прямо из лога без буферизации
        printf '{"log":'
        if [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
            awk 'BEGIN { ORS=""; print "\"" } { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); print $0 "\\n" } END { print "\"" }' "$LOG_FILE"
        else
            printf '"Лог пуст"'
        fi
        printf '}'
        ;;
esac
