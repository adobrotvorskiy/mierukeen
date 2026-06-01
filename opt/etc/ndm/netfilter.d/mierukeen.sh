#!/bin/sh
# Восстанавливает mierukeen iptables после того, как NDMS пересобирает
# netfilter (происходит при изменении настроек в UI, переподключении
# WAN/LAN интерфейсов и т.п.). Без этого хука цепочки MIERUKEEN и
# наша ip-rule молча пропадают, и трафик политики уходит мимо.

pidof mieru     >/dev/null 2>&1 || exit 0
pidof sing-box  >/dev/null 2>&1 || exit 0
[ -s /opt/etc/mkeen/policy_mark ] || exit 0

# Если все три якоря (nat-chain, mangle-chain, наш ip rule) на месте —
# выходим, ничего пересобирать не нужно.
iptables -t nat    -nL MIERUKEEN >/dev/null 2>&1 \
 && iptables -t mangle -nL MIERUKEEN >/dev/null 2>&1 \
 && ip rule show 2>/dev/null | grep -q 'fwmark 0x1ab.*lookup 100' \
 && exit 0

/opt/etc/init.d/S99mkeen ipt-refresh >/dev/null 2>&1
