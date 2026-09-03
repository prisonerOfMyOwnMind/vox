#!/bin/bash
# Создаёт постоянную подпись разработчика для Vox.
#
# Зачем. По умолчанию сборка подписывается ad-hoc, и отпечаток подписи меняется
# при КАЖДОЙ пересборке. macOS привязывает выданные разрешения — Универсальный
# доступ и Мониторинг ввода — к отпечатку, поэтому после каждой сборки они
# слетают, а старая запись в списке глушит повторный запрос.
#
# С постоянным сертификатом отпечаток не меняется, и разрешение выдаётся ОДИН раз.
#
# Сертификат самоподписанный и живёт только в вашей связке ключей. Он не делает
# приложение доверенным для других машин и никуда не отправляется.
#
# Запускать один раз. Потребуется пароль от учётной записи: последний шаг
# разрешает codesign пользоваться ключом без вопросов на каждой сборке.
set -euo pipefail

NAME="${VOX_IDENTITY_NAME:-Vox Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

die() { printf 'ОСТАНОВ: %s\n' "$1" >&2; exit 1; }

if security find-identity -v -p codesigning | grep -qF "$NAME"; then
    printf 'подпись «%s» уже существует, ничего делать не нужно\n' "$NAME"
    security find-identity -v -p codesigning | grep -F "$NAME"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf 'создаю самоподписанный сертификат «%s»\n' "$NAME"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null \
    || die "openssl не создал сертификат"

openssl pkcs12 -export -out "$WORK/identity.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout pass: \
    || die "openssl не собрал связку ключа и сертификата"

printf 'кладу в связку ключей (может спросить пароль)\n'
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "" \
    -T /usr/bin/codesign -T /usr/bin/security \
    || die "не удалось положить сертификат в связку ключей"

printf 'разрешаю codesign пользоваться ключом без вопросов\n'
printf 'macOS запросит пароль от учётной записи — введите его в системном окне\n'
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 \
    || printf 'ВНИМАНИЕ: не удалось снять вопрос про доступ к ключу.\n  Сборка всё равно подпишется, но macOS будет спрашивать разрешение каждый раз.\n  Нажмите «Всегда разрешать» в первом же окне.\n'

security find-identity -v -p codesigning | grep -F "$NAME" \
    || die "сертификат создан, но codesign его не видит"

printf '\nготово. Пересоберите приложение:\n  bash scripts/build-app.sh\n'
printf 'Дальше разрешения выдаются один раз и переживают пересборки.\n'
