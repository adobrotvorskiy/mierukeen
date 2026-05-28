#!/bin/sh
# Восстанавливает mierukeen iptables-цепочку после того, как NDMS
# пересобирает netfilter (что случается при изменении настроек в UI,
# перезагрузке WAN/LAN интерфейсов и т.п.). Без этого хука цепочка
# MIERUKEEN и хук в PREROUTING пропадают и трафик политики не
# проксируется до следующего вручную `mkeen -restart`.

# Срабатываем только если оба демона уже запущены.
pidof mieru     >/dev/null 2>&1 || exit 0
pidof sing-box  >/dev/null 2>&1 || exit 0

# Только если есть привязка к NDMS-политике.
[ -s /opt/etc/mkeen/policy_mark ] || exit 0

# Если наша цепочка ещё стоит — ничего не делаем.
iptables -t mangle -nL MIERUKEEN >/dev/null 2>&1 && \
    iptables -t mangle -C PREROUTING -m connmark \
        --mark "0x$(cat /opt/etc/mkeen/policy_mark | tr -d '[:space:]')" \
        -j MIERUKEEN >/dev/null 2>&1 && exit 0

/opt/etc/init.d/S99mkeen ipt-refresh >/dev/null 2>&1
