#!/bin/bash
# Собирает Vox.app: release-сборка, Info.plist, встроенная модель, подпись.
# Модель не скачивается здесь: её приносит scripts/fetch-model.sh (ветка stt).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PINS="$ROOT/swift/VoxCore/Pins.swift"
BUILD_DIR="$ROOT/.build"
APP="$BUILD_DIR/Vox.app"
# Постоянная подпись, если она заведена scripts/dev-identity.sh.
# Ad-hoc остаётся запасным вариантом, но с ним отпечаток меняется на каждой
# сборке, и выданные разрешения macOS слетают.
DEV_IDENTITY_NAME="${VOX_IDENTITY_NAME:-Vox Dev}"
if [ -n "${VOX_SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$VOX_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF "$DEV_IDENTITY_NAME"; then
    SIGN_IDENTITY="$DEV_IDENTITY_NAME"
else
    SIGN_IDENTITY="-"
fi
MANIFEST_NAME="vox-model-manifest.json"

die() { printf 'ОСТАНОВ: %s\n' "$1" >&2; exit 1; }

# Значения из Pins.swift, чтобы версия и раскладка модели не расходились с кодом.
pin() {
    local name="$1" value
    value="$(grep -E "static let $name = \"" "$PINS" | head -1 | sed -E 's/.*= "([^"]*)".*/\1/')"
    [ -n "$value" ] || die "в $PINS нет $name"
    printf '%s' "$value"
}

APP_VERSION="$(pin appVersion)"
MODEL_SUBPATH="$(pin modelBundleSubpath)"
MODEL_REPO="$(pin modelRepo)"
MODEL_REVISION="$(pin modelRevision)"
MODEL_NAME="$(basename "$MODEL_SUBPATH")"
MODEL_SRC="${VOX_MODEL_DIR:-$ROOT/models/$MODEL_NAME}"

# Проверяет каталог модели по его manifest: состав, размеры и SHA-256.
verify_model() {
    local dir="$1" label="$2" manifest="$1/$MANIFEST_NAME" plist index path size sha actual_size actual_sha
    [ -d "$dir" ] || die "$label: каталога модели нет: $dir"
    [ -f "$manifest" ] || die "$label: в каталоге модели нет $MANIFEST_NAME"

    plist="$(mktemp -t vox-manifest)"
    plutil -convert xml1 -o "$plist" "$manifest" || die "$label: $MANIFEST_NAME не разбирается"

    local repo revision
    repo="$(/usr/libexec/PlistBuddy -c 'Print :modelRepo' "$plist" 2>/dev/null || true)"
    revision="$(/usr/libexec/PlistBuddy -c 'Print :modelRevision' "$plist" 2>/dev/null || true)"
    [ "$repo" = "$MODEL_REPO" ] || die "$label: manifest про репозиторий $repo, а закреплён $MODEL_REPO"
    [ "$revision" = "$MODEL_REVISION" ] || die "$label: manifest про ревизию $revision, а закреплена $MODEL_REVISION"

    index=0
    while path="$(/usr/libexec/PlistBuddy -c "Print :entries:$index:path" "$plist" 2>/dev/null)"; do
        size="$(/usr/libexec/PlistBuddy -c "Print :entries:$index:sizeBytes" "$plist")"
        sha="$(/usr/libexec/PlistBuddy -c "Print :entries:$index:sha256" "$plist")"
        [ -f "$dir/$path" ] || die "$label: файла модели нет: $path"
        actual_size="$(stat -f%z "$dir/$path")"
        [ "$actual_size" = "$size" ] || die "$label: размер $path — $actual_size, ожидался $size"
        actual_sha="$(shasum -a 256 "$dir/$path" | cut -d' ' -f1)"
        [ "$actual_sha" = "$sha" ] || die "$label: SHA-256 $path не совпал"
        index=$((index + 1))
    done
    rm -f "$plist"
    [ "$index" -gt 0 ] || die "$label: manifest не перечисляет ни одного файла"
    printf 'модель проверена (%s): %d файлов\n' "$label" "$index"
}

printf 'release-сборка\n'
swift build -c release --package-path "$ROOT"
BINARY="$(swift build -c release --package-path "$ROOT" --show-bin-path)/Vox"
[ -x "$BINARY" ] || die "release-сборка не дала исполняемый файл $BINARY"

if [ ! -d "$MODEL_SRC" ]; then
    FETCH="$ROOT/scripts/fetch-model.sh"
    [ -x "$FETCH" ] || die "модели нет в $MODEL_SRC, а $FETCH отсутствует или не исполняемый. Скрипт получения модели делает ветка stt; после слияния запустите его или задайте VOX_MODEL_DIR."
    printf 'модели нет, вызываю %s\n' "$FETCH"
    "$FETCH"
fi
verify_model "$MODEL_SRC" "источник"

printf 'сборка bundle\n'
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Vox"
printf 'APPL????' > "$APP/Contents/PkgInfo"

sed "s/__VOX_VERSION__/$APP_VERSION/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null || die "Info.plist получился неверным"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true" ] \
    || die "в Info.plist нет LSUIElement"
/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$APP/Contents/Info.plist" > /dev/null \
    || die "в Info.plist нет описания доступа к микрофону"

MODEL_DEST="$APP/Contents/Resources/$MODEL_SUBPATH"
mkdir -p "$(dirname "$MODEL_DEST")"
cp -R "$MODEL_SRC" "$MODEL_DEST"
# Повторная проверка уже скопированного: копирование тоже может испортить файлы.
verify_model "$MODEL_DEST" "копия в bundle"

if [ "$SIGN_IDENTITY" = "-" ]; then
    printf 'подпись (ad-hoc): отпечаток меняется на каждой сборке, разрешения macOS будут слетать.\n'
    printf '  Постоянная подпись: bash scripts/dev-identity.sh\n'
else
    printf 'подпись (%s): постоянная, разрешения переживут пересборку\n' "$SIGN_IDENTITY"
fi
codesign --force --sign "$SIGN_IDENTITY" --identifier local.vox.Vox --timestamp=none "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

printf 'готово: %s\n' "$APP"
