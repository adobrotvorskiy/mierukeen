#!/bin/sh
# install.sh — установщик mierukeen на Keenetic с Entware.
#
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/adobrotvorskiy/mierukeen/main/scripts/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --upgrade
#   curl -fsSL .../install.sh | sh -s -- --version v0.1.0
#
# По умолчанию ставит последний релиз из github.com/adobrotvorskiy/mierukeen.

set -e

PROJECT="adobrotvorskiy/mierukeen"
GITHUB_API="https://api.github.com/repos/$PROJECT"
GITHUB_DL="https://github.com/$PROJECT/releases/download"
PREFIX="/opt"
TMPDIR="${TMPDIR:-/tmp}/mierukeen-install.$$"
ARCH=""
VERSION=""
UPGRADE=0

log() { echo "[install] $*"; }
die() { echo "[install] ERROR: $*" >&2; exit 1; }

# ── параметры ────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --upgrade) UPGRADE=1 ;;
        --version) VERSION="$2"; shift ;;
        --arch)    ARCH="$2"; shift ;;
        *) die "unknown arg: $1" ;;
    esac
    shift
done

# ── проверки окружения ──────────────────────────────────────────────
[ -d "$PREFIX" ] || die "нет $PREFIX — Entware не установлен?"
command -v opkg >/dev/null 2>&1 || die "нет opkg"
command -v curl >/dev/null 2>&1 || die "нет curl (opkg install curl)"

# ── определяем архитектуру ──────────────────────────────────────────
if [ -z "$ARCH" ]; then
    MACH="$(uname -m)"
    case "$MACH" in
        mips)    ARCH="mipsle-softfloat" ;;   # MT7621 (KN-1010/1810/...)
        mipsel)  ARCH="mipsle-softfloat" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *)       die "не поддерживаемая архитектура: $MACH" ;;
    esac
fi
log "целевая архитектура: $ARCH"

# ── зависимости из Entware ──────────────────────────────────────────
log "ставим зависимости из opkg"
opkg update >/dev/null 2>&1 || true
opkg install ca-bundle ca-certificates \
             iptables iptables-mod-tproxy iptables-mod-conntrack-extra \
             ip-full ipset jq \
             curl tar gzip >/dev/null

# ── определяем версию релиза ────────────────────────────────────────
if [ -z "$VERSION" ]; then
    log "ищем последний релиз"
    VERSION="$(curl -fsSL "$GITHUB_API/releases/latest" \
        | tr ',' '\n' | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/')"
    [ -n "$VERSION" ] || die "не удалось получить последний релиз — задай --version vX.Y.Z"
fi
log "версия: $VERSION"

# ── скачиваем tarball ──────────────────────────────────────────────
TARBALL="mierukeen-${VERSION}-${ARCH}.tar.gz"
URL="${GITHUB_DL}/${VERSION}/${TARBALL}"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT
log "качаю $URL"
curl -fL "$URL" -o "$TMPDIR/$TARBALL" || die "не удалось скачать $TARBALL"

# ── распаковка ──────────────────────────────────────────────────────
log "распаковываю в $PREFIX"
if [ "$UPGRADE" -eq 1 ] && [ -x "$PREFIX/etc/init.d/S99mkeen" ]; then
    log "stop старого инстанса"
    "$PREFIX/etc/init.d/S99mkeen" stop || true
fi

# Конфиги пользователя не перетираем
tar -xzf "$TMPDIR/$TARBALL" -C "$TMPDIR"
SRC="$TMPDIR/payload"
[ -d "$SRC" ] || SRC="$TMPDIR"

# бинари + скрипты — копируем всегда
cp "$SRC/opt/sbin/mieru"     "$PREFIX/sbin/mieru"
cp "$SRC/opt/sbin/sing-box"  "$PREFIX/sbin/sing-box"
cp "$SRC/opt/sbin/mkeen"     "$PREFIX/sbin/mkeen"
cp "$SRC/opt/etc/init.d/S99mkeen" "$PREFIX/etc/init.d/S99mkeen"
mkdir -p "$PREFIX/etc/ndm/netfilter.d"
cp "$SRC/opt/etc/ndm/netfilter.d/mierukeen.sh" "$PREFIX/etc/ndm/netfilter.d/mierukeen.sh"
chmod +x "$PREFIX/sbin/mieru" "$PREFIX/sbin/sing-box" "$PREFIX/sbin/mkeen" \
         "$PREFIX/etc/init.d/S99mkeen" \
         "$PREFIX/etc/ndm/netfilter.d/mierukeen.sh"

# дефолтные конфиги — только если профиля ещё нет
mkdir -p "$PREFIX/etc/mkeen/profiles/default" "$PREFIX/var/log" \
         "$PREFIX/var/run" "$PREFIX/var/lib/sing-box"
for f in mieru.json singbox.json; do
    dst="$PREFIX/etc/mkeen/profiles/default/$f"
    if [ ! -f "$dst" ]; then
        cp "$SRC/opt/etc/mkeen/profiles/default/$f" "$dst"
        log "создан $dst"
    else
        log "оставляю существующий $dst"
    fi
done
[ -L "$PREFIX/etc/mkeen/active" ] || \
    ln -sfn "$PREFIX/etc/mkeen/profiles/default" "$PREFIX/etc/mkeen/active"

# ── cron-watchdog: каждую минуту проверяет демонов, поднимает если лежат
WATCHDOG_LINE="* * * * * /opt/etc/init.d/S99mkeen check >/dev/null 2>&1 || /opt/etc/init.d/S99mkeen start >/dev/null 2>&1 # mierukeen-watchdog"
if ! crontab -l 2>/dev/null | grep -q 'mierukeen-watchdog'; then
    ( crontab -l 2>/dev/null; echo "$WATCHDOG_LINE" ) | crontab -
    log "установлен cron-watchdog (каждую минуту)"
fi

# ── авто-привязка к NDMS политике "Mierukeen" (если уже создана) ────
NDMS_POLICY_NAME="${NDMS_POLICY_NAME:-Mierukeen}"
echo "$NDMS_POLICY_NAME" > "$PREFIX/etc/mkeen/policy_name"
POLICY_MARK="$(curl -kfsS "http://localhost:79/rci/show/ip/policy" 2>/dev/null \
    | jq -r --arg n "$NDMS_POLICY_NAME" \
        '.[] | select(.description | ascii_downcase == ($n | ascii_downcase)) | .mark' \
    2>/dev/null | head -1)"
if [ -n "$POLICY_MARK" ] && [ "$POLICY_MARK" != "null" ]; then
    echo "$POLICY_MARK" > "$PREFIX/etc/mkeen/policy_mark"
    log "найдена NDMS политика '$NDMS_POLICY_NAME' (mark=0x$POLICY_MARK) — привязано"
    BOUND=1
else
    log "NDMS политика '$NDMS_POLICY_NAME' не найдена — создай в UI и запусти 'mkeen ndms detect'"
    BOUND=0
fi

cat <<EOF

✓ mierukeen ${VERSION} установлен.

Дальше:
  1) Отредактируй mieru-профиль: $PREFIX/etc/mkeen/profiles/default/mieru.json
     (REPLACE_ME_* поля — креды и адрес твоего mieru-сервера)
EOF

if [ "$BOUND" -eq 0 ]; then
    cat <<EOF
  2) В админке Keenetic (Сетевые правила → Политики или Профили доступа)
     создай политику с именем "${NDMS_POLICY_NAME}". Далее привяжи к ней
     устройства, которые должны ходить через mieru.
  3) На роутере: mkeen ndms detect
EOF
fi

cat <<EOF
  $( [ "$BOUND" -eq 1 ] && echo "2" || echo "4" )) Привяжи устройства к политике "${NDMS_POLICY_NAME}" в UI Keenetic.
  $( [ "$BOUND" -eq 1 ] && echo "3" || echo "5" )) Старт:        mkeen -start
     Статус:       mkeen -status
     Логи:         mkeen -log
  $( [ "$BOUND" -eq 1 ] && echo "4" || echo "6" )) Проверь с привязанного устройства: curl https://ifconfig.me
     (должен показать IP mieru-сервера)

Документация: https://gitlab.com/${PROJECT}
EOF
