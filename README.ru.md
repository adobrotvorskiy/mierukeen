[English version →](README.md)

# mierukeen

**mieru + sing-box для роутеров Keenetic с Entware.**

Дистрибутив в стиле [xkeen](https://github.com/Skrill0/XKeen), но с другим стеком:
- **[mieru](https://github.com/enfein/mieru)** — обфусцированный SOCKS5-транспорт (клиент)
- **[sing-box](https://github.com/SagerNet/sing-box)** — routing engine: REDIRECT/TPROXY inbound-ы, geoip/geosite, правила по доменам/CIDR, Clash API
- **`mkeen`** — CLI поверх двух: лайфсайкл + профили + маршруты + привязка к NDMS-политике

Целевое железо: **Keenetic Titan (KN-1810)** и любые Keenetic на MT7621 (mipsel softfloat). CI также собирает arm64-тарбол для других моделей.

## Установка

На роутере (с уже установленной Entware):

```sh
curl -fsSL https://raw.githubusercontent.com/adobrotvorskiy/mierukeen/main/scripts/install.sh | sh
```

**Перед стартом**:

1. В UI Keenetic зайди в **Сетевые правила → Политики** (или **Профили доступа** в новых прошивках) и создай политику с именем `Mierukeen`.
2. **Обязательно отметь внутри неё хотя бы одно интернет-соединение** (обычно — твой основной провайдер / WAN). Без этого NDMS отвечает `Refused` на DNS-запросы от устройств политики, и они вообще не получают интернета — даже до sing-box не доходят. По факту трафик пойдёт **не** через это соединение благодаря нашим iptables-правилам, но Keenetic так разрешит DNS.
3. Привяжи к ней устройства, которые должны ходить через mieru (Мои сети и Wi-Fi → конкретное устройство → закрепить за политикой).
4. Отредактируй mieru-профиль на роутере: `vi /opt/etc/mkeen/profiles/default/mieru.json` — впиши свой mieru-сервер (поля `REPLACE_ME_*`).
5. Привяжи mkeen к политике (если установщик не сделал это сам):

```sh
mkeen ndms detect       # ищет политику Mierukeen, сохраняет её mark
mkeen ndms status       # показывает текущую привязку
```

6. Запусти:

```sh
mkeen -start
mkeen -status
mkeen -log
```

Проверка с устройства, привязанного к политике в UI:

```
curl https://ifconfig.me   # должен быть IP mieru-сервера
```

Устройства, **не** привязанные к политике, продолжат ходить напрямую через WAN — это и есть смысл `xkeen`-style интеграции.

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
mkeen route reload                         # = mkeen -restart
```

Правила пишутся прямо в `singbox.json` активного профиля и помечаются `"_mkeen_user": true` — это позволяет их потом удалять. По умолчанию приклеиваются в начало `route.rules` (имеют приоритет над `geoip-ru` / `geosite-category-ru`).

Если хочется сложнее — редактируй `singbox.json` руками, формат описан в [sing-box docs](https://sing-box.sagernet.org/configuration/route/).

## Удалённое управление через Karing / yacd

В дефолтном `singbox.json` включён Clash API на `127.0.0.1:9090` с заглушкой секрета `CHANGE_ME_CLASH_SECRET`. Открой его на LAN-интерфейс, поставь свой секрет — и подключайся Karing'ом / yacd / metacubexd как к локальному клиенту. Маршруты переключаются на лету, без правки конфига.

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
  -> NDMS ставит fwmark $POLICY_MARK на пакеты устройств в политике Mierukeen
  -> TCP: nat    PREROUTING -m connmark --mark $POLICY_MARK -p tcp -j MIERUKEEN
                  MIERUKEEN: bypass private + REDIRECT --to-ports 7895
  -> UDP: mangle PREROUTING -m connmark --mark $POLICY_MARK -p udp -j MIERUKEEN
                  MIERUKEEN: bypass private + TPROXY --on-port 7896
                                                       |
                                                  sing-box
                                                       |
                                            +----------+----------+
                                            v          v          v
                                       mieru-out    direct      block
                                       (SOCKS5
                                        :1080)
                                            |
                                            v
                                       mieru-сервер
```

- **NDMS Policy интеграция (xkeen-style):** Keenetic сам ставит на пакеты от устройств в политике fwmark, специфичный для этой политики. `mkeen ndms detect` достаёт mark из локального NDMS REST API `http://localhost:79/rci/show/ip/policy` (то же, что использует web-UI) и сохраняет в `/opt/etc/mkeen/policy_mark`.
- Перехватывается **только** трафик с этим mark — никакие другие LAN-устройства не затрагиваются.
- TCP идёт через `nat REDIRECT`, UDP — через `mangle TPROXY`, на разных портах. Разделение намеренное: на Linux 4.9 (ядро Keenetic) TPROXY для TCP не доставляет пакеты в локальный listener, поэтому повторяем «Mixed_1» паттерн от xkeen.
- sing-box по правилам решает: RU geoip/geosite — direct, реклама — block, всё остальное — SOCKS5 на mieru.
- mieru обфусцирует SOCKS-трафик и пробрасывает на сервер.

С xkeen совместимо: можно держать обе политики одновременно (XKeen → xray, Mierukeen → mieru) и переключать устройства между ними мышкой.

## Структура репозитория

```
opt/
  etc/
    init.d/S99mkeen                # init для Entware
    ndm/netfilter.d/mierukeen.sh   # переустанавливает iptables после перестроек NDMS
    mkeen/profiles/default/        # дефолтный профиль
      mieru.json
      singbox.json
  sbin/mkeen                       # CLI
scripts/
  install.sh                       # установщик
build/
  versions.env                     # пиннинг mieru / sing-box версий
.github/workflows/release.yml      # кросс-сборка -> GitHub Release
```

## Релизы

GitHub Actions собирает на каждый тег `vX.Y.Z` два архива: `mierukeen-vX.Y.Z-mipsle-softfloat.tar.gz` и `…-arm64.tar.gz`. Они публикуются как [GitHub Releases](https://github.com/adobrotvorskiy/mierukeen/releases) и тянутся `install.sh` через `releases/download/vX.Y.Z/…`.

## Лицензия

MIT (исходники mierukeen). Бинари mieru / sing-box — под их собственными лицензиями.
