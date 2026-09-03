#!/bin/bash
# Заводит постоянную подпись разработчика для Vox.
#
# Зачем. По умолчанию сборка подписывается ad-hoc, и отпечаток подписи меняется
# при КАЖДОЙ пересборке. macOS привязывает выданные разрешения — Микрофон,
# Универсальный доступ, Мониторинг ввода — к отпечатку, поэтому после каждой
# сборки они слетают, а протухшая запись в списке глушит повторный запрос.
# С постоянным сертификатом разрешения выдаются один раз.
#
# Что скрипт делает с системой, по-честному:
#   1. создаёт самоподписанный сертификат в вашей связке ключей;
#   2. помечает его доверенным ДЛЯ ПОДПИСИ КОДА — это `sudo`, спросит пароль
#      администратора. Без этого шага codesign отвечает «no identity found»:
#      недоверенным сертификатом macOS подписывать не даёт.
#
# Сертификат никуда не отправляется, действует только на этой машине и не делает
# приложение доверенным для кого-то ещё. Удалить: см. конец вывода.
#
# Проверено опытом, а не предположением: связка ключей macOS не читает PKCS#12
# от Homebrew OpenSSL 3 (шифрование AES-256-CBC) и не принимает пустой пароль.
# Поэтому здесь жёстко системный /usr/bin/openssl и непустой временный пароль.
set -euo pipefail

NAME="${VOX_IDENTITY_NAME:-Vox Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl

die() { printf 'ОСТАНОВ: %s\n' "$1" >&2; exit 1; }

[ -x "$OPENSSL" ] || die "нет системного $OPENSSL"

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
    printf 'подпись «%s» уже заведена\n' "$NAME"
    security find-identity -p codesigning | grep -F "\"$NAME\""
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="vox-$(date +%s)-$RANDOM"   # временный, живёт только внутри этого запуска

printf 'создаю самоподписанный сертификат «%s»\n' "$NAME"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null \
    || die "openssl не создал сертификат"

"$OPENSSL" pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout "pass:$PASS" \
    || die "openssl не собрал связку ключа и сертификата"

printf 'кладу в связку ключей\n'
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign \
    || die "не удалось положить сертификат в связку ключей"

printf '\nтеперь нужен пароль АДМИНИСТРАТОРА: помечаю сертификат доверенным\n'
printf 'для подписи кода. Без этого codesign им пользоваться откажется.\n'
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain "$WORK/cert.pem" \
    || die "не удалось пометить сертификат доверенным. Разрешения будут слетать при каждой пересборке; можно продолжать без постоянной подписи."

printf '\nпроверяю, что подпись реально работает\n'
cp /bin/echo "$WORK/probe" && chmod u+w "$WORK/probe"
codesign --force --sign "$NAME" --identifier local.vox.probe --timestamp=none "$WORK/probe" \
    || die "codesign не смог подписать пробный файл этим сертификатом"
codesign --verify --strict "$WORK/probe" || die "подпись пробного файла не проходит проверку"

printf '\nготово. Подпись «%s» работает.\n' "$NAME"
printf 'Дальше:  cd %s && bash scripts/build-app.sh && bash scripts/install.sh\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
printf '\nУдалить подпись, если больше не нужна:\n'
printf '  sudo security delete-certificate -c "%s" /Library/Keychains/System.keychain\n' "$NAME"
printf '  security delete-identity -c "%s"\n' "$NAME"
