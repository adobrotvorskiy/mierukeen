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

**Перед стартом**:

1. В UI Keenetic зайди в **Сетевые правила → Политики** (или **Профили доступа** в новых прошивках) и создай политику с именем `Mierukeen`. Подключения внутри неё можно оставить пустыми — она нужна только как «контейнер» для маркировки трафика.
2. Привяжи к ней устройства, которые должны ходить через mieru (Мои сети и Wi-Fi → конкретное устройство → закрепить за политикой).
3. Отредактируй mieru-профиль на роутере: `vi /opt/etc/mkeen/profiles/default/mieru.json` — впиши свой mieru-сервер (`REPLACE_ME_*`).
4. Привяжи mkeen к политике (если установщик не сделал это сам):

```sh
mkeen ndms detect       # ищет политику Mierukeen, сохраняет её mark
mkeen ndms status       # показывает текущую привязку
```

5. Запусти:

```sh
mkeen -start
mkeen -status
mkeen -log
```

Проверка с устройства, привязанного к политике в UI:

```
curl https://ifconfig.me   # должен быть IP mieru-сервера
```

Устройства, не привязанные к политике, продолжат ходить напрямую через WAN — это и есть смысл `xkeen`-style интеграции.

## Профили

```sh
mkeen profile list           # с маркером * на активном
mkeen profile add work       # клон с default
mkeen profile use work
mkeen profile show           # текущий конфиг
mkeen profile rm work
```

Каждый профиль — папка `/opt/etc/mkeen/profiles/<name>/` с `mieru.json` и `singbox.json`. Активный — symlink `/opt/etc/mkeen/active`.

## NDMS Policy

```sh
mkeen ndms detect [name]   # найти mark по имени политики (default: Mierukeen)
mkeen ndms bind <mark>     # задать вручную (если автодетект не сработал)
mkeen ndms unbind          # отвязать (mkeen перестанет перехватывать)
mkeen ndms status          # текущая привязка
```

Имя политики хранится в `/opt/etc/mkeen/policy_name`, mark — в `/opt/etc/mkeen/policy_mark`. После любой смены — `mkeen -restart`.

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
LAN-client -> Keenetic
  -> NDMS ставит mark $POLICY_MARK на пакеты устройств в политике Mierukeen
  -> mangle PREROUTING -m connmark --mark $POLICY_MARK -j MIERUKEEN
  -> MIERUKEEN: bypass private nets + TPROXY -> sing-box :7895
                                                       |
                                              (route rules)
                                                       |
                                          +------------+----------+
                                          v            v          v
                                    mieru (SOCKS5)   direct     block
                                       :1080
                                          |
                                          v
                                    mieru-server
```

- **NDMS Policy интеграция (xkeen-style):** Keenetic сам ставит на пакеты от устройств в политике fwmark, специфичный для этой политики. `mkeen ndms detect` достаёт mark из локального API `http://localhost:79/rci/show/ip/policy` (то же, что использует web-UI) и сохраняет в `/opt/etc/mkeen/policy_mark`.
- В `mangle PREROUTING` перехватывается **только** трафик с этим mark — никакие другие LAN-устройства не затрагиваются.
- В цепочке `MIERUKEEN` приватные сети идут `RETURN`, остальное помечается `fwmark 0x1` и уходит на tproxy-инбаунд sing-box (через `ip rule` + локальная табличка 100).
- sing-box по правилам решает: RU/приватные сети — direct, реклама — block, всё остальное — в SOCKS5 на mieru.
- mieru обфусцирует и пробрасывает на сервер.

С xkeen совместимо: можно держать обе политики одновременно (XKeen → xray, Mierukeen → mieru) и переключать устройства между ними мышкой.

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
