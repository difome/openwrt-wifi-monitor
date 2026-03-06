# WiFi Monitor для OpenWrt

Монитор подключенных устройств по Wi-Fi с отправкой логов и статуса в Telegram.

## Установка WiFi Monitor

Вкратце, достаточно одного скрипта для установки и обновления. Скопируйте и выполните эту команду в терминале роутера (SSH):

```sh
sh <(wget -O - https://raw.githubusercontent.com/difome/openwrt-wifi-monitor/refs/heads/main/install.sh)
```

## Удаление WiFi Monitor

```sh
/etc/init.d/wifi_monitor stop 2>/dev/null
/etc/init.d/wifi_monitor disable 2>/dev/null
rm -f /etc/init.d/wifi_monitor
rm -f /usr/bin/wifi_monitor.sh
rm -f /usr/bin/wifi_monitor_rpc.sh
rm -f /usr/bin/wifi_monitor_clients.sh
rm -f /usr/bin/wifi_monitor_test.sh
rm -f /etc/config/wifi_monitor
rm -f /etc/wifi_monitor_version
rm -f /usr/share/luci/menu.d/luci-app-wifi-monitor.json
rm -f /usr/share/rpcd/acl.d/luci-app-wifi-monitor.json
rm -rf /www/luci-static/resources/view/wifi_monitor
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```
