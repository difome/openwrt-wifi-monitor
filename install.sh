#!/bin/sh
set -e

echo "==> Скачиваем файлы проекта..."
DL_DIR="/tmp/wifi_monitor_install"
rm -rf "$DL_DIR"
mkdir -p "$DL_DIR"
wget -qO "$DL_DIR/main.tar.gz" "https://github.com/difome/openwrt-wifi-monitor/archive/refs/heads/main.tar.gz"
tar -xzf "$DL_DIR/main.tar.gz" -C "$DL_DIR"
BASE="$DL_DIR/openwrt-wifi-monitor-main"

echo "==> Устанавливаем зависимости..."
opkg update >/dev/null 2>&1
opkg install curl iw 2>/dev/null || true

echo "==> UCI конфиг..."
if [ ! -f /etc/config/wifi_monitor ]; then
    cp "$BASE/etc/config/wifi_monitor" /etc/config/wifi_monitor
    echo "    создан"
else
    echo "    уже есть, пропускаем"
fi

echo "==> Скрипты..."
cp "$BASE/usr/bin/wifi_monitor.sh"         /usr/bin/wifi_monitor.sh
cp "$BASE/usr/bin/wifi_monitor_rpc.sh"     /usr/bin/wifi_monitor_rpc.sh
cp "$BASE/usr/bin/wifi_monitor_clients.sh" /usr/bin/wifi_monitor_clients.sh
cp "$BASE/usr/bin/wifi_monitor_test.sh"    /usr/bin/wifi_monitor_test.sh
chmod 755 /usr/bin/wifi_monitor.sh \
          /usr/bin/wifi_monitor_rpc.sh \
          /usr/bin/wifi_monitor_clients.sh \
          /usr/bin/wifi_monitor_test.sh

echo "==> init.d служба..."
cp "$BASE/etc/init.d/wifi_monitor" /etc/init.d/wifi_monitor
chmod 755 /etc/init.d/wifi_monitor
/etc/init.d/wifi_monitor enable 2>/dev/null || true

echo "==> LuCI menu.d..."
cp "$BASE/usr/share/luci/menu.d/luci-app-wifi-monitor.json" \
   /usr/share/luci/menu.d/luci-app-wifi-monitor.json

echo "==> rpcd ACL..."
cp "$BASE/usr/share/rpcd/acl.d/luci-app-wifi-monitor.json" \
   /usr/share/rpcd/acl.d/luci-app-wifi-monitor.json

echo "==> LuCI JS view..."
mkdir -p /www/luci-static/resources/view/wifi_monitor
chmod 755 /www/luci-static/resources/view/wifi_monitor
cp "$BASE/usr/share/luci/view/wifi_monitor/main.js" \
   /www/luci-static/resources/view/wifi_monitor/main.js
chmod 644 /www/luci-static/resources/view/wifi_monitor/main.js

echo "==> Чистим старые файлы если остались..."
rm -f /usr/lib/lua/luci/controller/wifi_monitor.lua
rm -rf /usr/lib/lua/luci/view/wifi_monitor
rm -rf /www/luci-static/resources/view/wifi-monitor

echo "==> Чистим кэш LuCI..."
rm -f /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo "==> Перезапускаем rpcd и uhttpd..."
/etc/init.d/rpcd restart
sleep 1
/etc/init.d/uhttpd restart

echo "==> Убираем за собой..."
rm -rf "$DL_DIR"

echo ""
echo "✅ Готово!"
echo "   Открывай: LuCI → Services → WiFi Monitor"
echo "   Вписывай Bot Token и Chat ID, жми Сохранить"
