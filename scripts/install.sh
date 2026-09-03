#!/bin/bash
# Ставит собранное Vox.app в /Applications и запускает.
#
# Существует потому, что установка «в лоб» ломается: если удалить bundle из-под
# работающего приложения, macOS снимает его иконку из menu bar, а процесс
# остаётся жить без интерфейса. Сначала выход, потом замена.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/.build/Vox.app"
DEST="/Applications/Vox.app"

die() { printf 'ОСТАНОВ: %s\n' "$1" >&2; exit 1; }

[ -d "$SRC" ] || die "нет собранного приложения в $SRC. Сначала: bash scripts/build-app.sh"

if pgrep -qf "$DEST/Contents/MacOS/Vox"; then
    printf 'выхожу из работающего Vox\n'
    osascript -e 'tell application "Vox" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -qf "$DEST/Contents/MacOS/Vox" || break
        sleep 0.5
    done
    if pgrep -qf "$DEST/Contents/MacOS/Vox"; then
        pkill -f "$DEST/Contents/MacOS/Vox" || true
        sleep 1
    fi
    pgrep -qf "$DEST/Contents/MacOS/Vox" && die "Vox не завершился, закройте его вручную"
fi

rm -rf "$DEST"
cp -R "$SRC" "$DEST" || die "не удалось скопировать в $DEST"
codesign --verify --strict "$DEST" || die "подпись установленного приложения не проходит проверку"

SIG=$(codesign -dv --verbose=2 "$DEST" 2>&1 | grep -E '^Signature=' | cut -d= -f2)
printf 'установлено: %s (подпись: %s)\n' "$DEST" "$SIG"
if [ "$SIG" = "adhoc" ]; then
    printf 'ВНИМАНИЕ: подпись ad-hoc. Выданные разрешения слетят при следующей пересборке.\n'
    printf '  Постоянная подпись: bash scripts/dev-identity.sh, затем пересоберите и поставьте заново.\n'
fi

open "$DEST" || die "LaunchServices не смог запустить $DEST"

# Не рапортовать об успехе, не убедившись. Раньше скрипт печатал «запущено»
# сразу после open, и запуск, не успевший состояться, выглядел как успешный.
for _ in $(seq 1 20); do
    pgrep -qf "$DEST/Contents/MacOS/Vox" && break
    sleep 0.5
done
pgrep -qf "$DEST/Contents/MacOS/Vox" \
    || die "приложение не поднялось за 10 с. Журнал: log show --predicate 'subsystem == \"local.vox.Vox\"' --last 5m"

printf 'запущено (pid %s). Иконка микрофона должна появиться в menu bar.\n' \
    "$(pgrep -f "$DEST/Contents/MacOS/Vox" | head -1)"
