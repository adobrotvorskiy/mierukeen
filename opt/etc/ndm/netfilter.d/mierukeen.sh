#!/bin/sh
# Восстанавливает mierukeen после того, как NDMS пересобирает netfilter
# (происходит при изменении настроек в UI, переподключении WAN/LAN
# интерфейсов и т.п.). Также страхует случай когда демоны не были
# подняты при ребуте — пробуем поднять весь стек целиком.

PATH="/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin"

[ -s /opt/etc/mkeen/policy_mark ] || exit 0

# Если хотя бы один из демонов лежит — поднимаем весь стек заново.
# Иначе iptables-цепочки и так не могли бы корректно работать.
if ! pidof mieru >/dev/null 2>&1 || ! pidof sing-box >/dev/null 2>&1; then
    /opt/etc/init.d/S99mkeen start >/dev/null 2>&1
    exit 0
fi

# Демоны живы — проверяем что все три якоря (nat-chain, mangle-chain,
# ip rule fwmark 0x1ab → 100) на месте. Если да — выходим.
iptables -t nat    -nL MIERUKEEN >/dev/null 2>&1 \
 && iptables -t mangle -nL MIERUKEEN >/dev/null 2>&1 \
 && ip rule show 2>/dev/null | grep -q 'fwmark 0x1ab.*lookup 100' \
 && exit 0

/opt/etc/init.d/S99mkeen ipt-refresh >/dev/null 2>&1
