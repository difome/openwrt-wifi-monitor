#!/bin/sh
# /usr/bin/wifi_monitor_clients.sh
# Выводит текущих клиентов в формате TSV: MAC\tHostname\tIP\tIface

for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do
    iw dev "$iface" station dump 2>/dev/null | grep "^Station" | while read _ mac _; do
        mac_lower=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
        hostname=$(awk -v m="$mac_lower" 'tolower($2)==m{print $4; exit}' /tmp/dhcp.leases 2>/dev/null)
        ip=$(awk -v m="$mac_lower" 'tolower($2)==m{print $3; exit}' /tmp/dhcp.leases 2>/dev/null)
        [ -z "$hostname" ] || [ "$hostname" = "*" ] && hostname="неизвестно"
        printf '%s\t%s\t%s\t%s\n' "$mac" "$hostname" "$ip" "$iface"
    done
done
