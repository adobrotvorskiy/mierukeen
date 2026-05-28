# mierukeen

**mieru + sing-box для роутеров Keenetic с Entware.**

Дистрибутив в стиле [xkeen](https://github.com/Skrill0/XKeen), но с другим стеком:
- **[mieru](https://github.com/enfein/mieru)** — обфусцированный SOCKS5-транспорт (клиент)
- **[sing-box](https://github.com/SagerNet/sing-box)** — routing engine: tproxy на роутере, geoip/geosite, правила по доменам/CIDR, Clash API
- **`mkeen`** — CLI поверх двух, лайфсайкл + профили + маршруты

Целевое железо: **Keenetic Titan (KN-1810)** и любые Keenetic на MT7621 (mipsel softfloat). CI также собирает под arm64 для других моделей.

## Установка

На роутере (с уже установленной Entware):

```sh
curl -fsSL https://gitlab.com/adobrotvorskiy/mierukeen/-/raw/main/scripts/install.sh | sh
```

Дальше:

1. Отредактируй `/opt/etc/mkeen/profiles/default/mieru.json` — впиши адрес/порт/креды своего mieru-сервера на месте `REPLACE_ME_*`.
2. По желанию подкрути `singbox.json` (например, измени `clash_api.secret`, добавь свой DNS).
3. Запусти:

```sh
mkeen -start
mkeen -status
mkeen -log
```

Проверка с LAN-клиента (телефон, ноут в той же сети):

```
curl https://ifconfig.me   # должен быть IP mieru-сервера
```

## Профили

```sh
mkeen profile list           # с маркером * на активном
mkeen profile add work       # клон с default
mkeen profile use work
mkeen profile show           # текущий конфиг
mkeen profile rm work
```

Каждый профиль — папка `/opt/etc/mkeen/profiles/<name>/` с `mieru.json` и `singbox.json`. Активный — symlink `/opt/etc/mkeen/active`.

## Маршруты

```sh
mkeen route add youtube.com       proxy   # домен -> mieru
mkeen route add 1.2.3.0/24        direct  # подсеть -> напрямую
mkeen route add ads.example.com   block   # -> выкинуть

mkeen route list
mkeen route del youtube.com
mkeen route reload                 # = mkeen -restart
```

Правила пишутся прямо в `singbox.json` активного профиля и помечаются `"_mkeen_user": true` — это позволяет их потом удалять. По умолчанию приклеиваются в начало `route.rules` (имеют приоритет над `geoip-ru`/`geosite-ru`).

Если хочется сложнее — редактируй `singbox.json` руками, формат описан в [sing-box docs](https://sing-box.sagernet.org/configuration/route/).

## Удалённое управление через Karing / yacd

В дефолтном `singbox.json` включён Clash API на `127.0.0.1:9090` с секретом `CHANGE_ME_CLASH_SECRET`. Открой его на LAN-интерфейс, поставь свой секрет — и подключайся Karing'ом/yacd'ом как к локальному клиенту. Маршруты переключаются на лету, без правки конфига.

```json
"experimental": {
  "clash_api": {
    "external_controller": "192.168.1.1:9090",
    "secret": "TVOJ_DLINNYJ_SEKRET"
  }
}
```

## Что под капотом

```
client (LAN) -> Keenetic -[iptables mangle TPROXY]-> sing-box :7895
                                                     |
                                            (route rules)
                                                     |
                                        +------------+----------+
                                        v            v          v
                                  mieru (SOCKS5)   direct      block
                                     :1080
                                        |
                                        v
                                  mieru-server
```

- LAN-трафик заворачивается в `mangle PREROUTING` цепочку `MIERUKEEN`, помечается `fwmark 0x1`, через `ip rule` уходит в локальную табличку `100` и попадает на tproxy-инбаунд sing-box на порту 7895.
- sing-box по правилам решает: RU/приватные сети — direct, реклама — block, всё остальное — в SOCKS5 на mieru.
- mieru обфусцирует и пробрасывает на сервер.

## Структура репозитория

```
opt/
  etc/
    init.d/S99mkeen            # init для Entware
    mkeen/profiles/default/    # дефолтный профиль
      mieru.json
      singbox.json
  sbin/mkeen                   # CLI
scripts/
  install.sh                   # установщик
build/
  versions.env                 # пиннинг mieru/sing-box версий
.gitlab-ci.yml                 # кросс-сборка -> release
```

## Релизы

GitLab CI собирает на каждый тег `vX.Y.Z` два архива: `mierukeen-vX.Y.Z-mipsle-softfloat.tar.gz` и `...-arm64.tar.gz`. Они доступны через release links и используются `install.sh`.

## Лицензия

MIT (исходники mierukeen). Бинари mieru/sing-box — под их собственными лицензиями.
