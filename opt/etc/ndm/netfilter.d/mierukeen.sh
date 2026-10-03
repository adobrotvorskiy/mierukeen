#!/bin/sh
# NDMS пересобирает таблицы netfilter по одной (изменение настроек в UI,
# переподключение интерфейсов и т.п.) и после каждой вызывает этот хук с
# $type и $table. Возвращаем только нашу часть этой таблицы, атомарно и не
# трогая остальные (S99mkeen ensure). Прежний ipt-refresh на каждый вызов
# сначала удалял все наши правила, и трафик политики десятки секунд шёл мимо
# туннеля. Если демоны лежат — поднимаем стек целиком. Подстраховка на случай,
# когда NDMS меняет таблицу без вызова хука: cron раз в минуту (mierukeen-ensure).

PATH="/opt/bin:/opt/sbin:/sbin:/bin:/usr/sbin:/usr/bin"

[ "$type" = "ip6tables" ] && exit 0
case "$table" in filter|raw) exit 0 ;; esac
[ -s /opt/etc/mkeen/policy_mark ] || exit 0

if ! pidof mieru >/dev/null 2>&1 || ! pidof sing-box >/dev/null 2>&1; then
    /opt/etc/init.d/S99mkeen start >/dev/null 2>&1
    exit 0
fi

exec /opt/etc/init.d/S99mkeen ensure "$table" ndm
