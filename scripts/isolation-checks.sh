#!/bin/bash
# Доказательства изоляции на собранном приложении.
#
# Не «приложение офлайн», а фактический вывод неудачных попыток. Каждая проверка
# печатает то, что реально ответила система.
#
# Работает на КОПИИ приложения в .build: установленное в /Applications не трогает.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/Vox.app"
WORK="$ROOT/.build/isolation"
BIN="$APP/Contents/MacOS/Vox"
PASS=0; FAIL=0

hdr() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf 'ПРОЙДЕНО: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf 'ПРОВАЛ:   %s\n' "$1"; FAIL=$((FAIL+1)); }

[ -x "$BIN" ] || { echo "нет собранного приложения, сначала bash scripts/build-app.sh"; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK"

hdr "1. Запрет исходящей сети применяется и действует"
OUT="$("$BIN" --self-test 2>&1 | grep -E 'запрет (исходящей )?сети' || true)"
printf '%s\n' "$OUT"
if printf '%s' "$OUT" | grep -q 'seatbelt' && printf '%s' "$OUT" | grep -q 'PASS.*соединение отклонено'; then
    ok "механизм назван, соединение отклонено"
else
    bad "нет доказательства запрета сети"
fi

hdr "2. Отсутствующая модель НЕ запускает загрузку"
cp -R "$APP" "$WORK/NoModel.app"
rm -rf "$WORK/NoModel.app/Contents/Resources/Models"
OUT="$("$WORK/NoModel.app/Contents/MacOS/Vox" --self-test 2>&1 | grep -viE '^\[' || true)"
printf '%s\n' "$OUT" | grep -iE 'модель|FAIL|итого' | head -6
RECREATED="нет"
[ -d "$WORK/NoModel.app/Contents/Resources/Models" ] && RECREATED="ДА"
printf 'каталог модели создан заново: %s\n' "$RECREATED"
if printf '%s' "$OUT" | grep -qiE 'модель (отсутствует|не найдена)|FAIL'; then
    if printf '%s' "$OUT" | grep -qiE 'download|скачив|загружа' || [ "$RECREATED" = "ДА" ]; then
        bad "есть признаки загрузки или каталог восстановлен"
    else
        ok "отказ без попытки скачать, каталог не восстановлен"
    fi
else
    bad "отсутствие модели не обнаружено"
fi

hdr "3. Повреждённая модель НЕ запускает починку"
cp -R "$APP" "$WORK/Broken.app"
VICTIM="$(find "$WORK/Broken.app/Contents/Resources/Models" -name 'parakeet_vocab.json' | head -1)"
printf 'X' >> "$VICTIM"
BEFORE="$(find "$WORK/Broken.app/Contents/Resources/Models" -type f | wc -l | tr -d ' ')"
OUT="$("$WORK/Broken.app/Contents/MacOS/Vox" --self-test 2>&1 | grep -viE '^\[' || true)"
printf '%s\n' "$OUT" | grep -iE 'поврежд|изменен|FAIL|итого' | head -5
AFTER="$(find "$WORK/Broken.app/Contents/Resources/Models" -type f | wc -l | tr -d ' ')"
if printf '%s' "$OUT" | grep -qiE 'поврежд|изменен' && [ "$BEFORE" = "$AFTER" ]; then
    ok "отказ, каталог модели не тронут ($BEFORE файлов до и после)"
else
    bad "повреждение не обнаружено либо каталог изменён ($BEFORE -> $AFTER)"
fi

hdr "4. Расшифровка не попадает в журнал"
FIX="$ROOT/fixtures/audio/dev-02.wav"
if [ -f "$FIX" ]; then
    RAW="$("$BIN" --transcribe-file "$FIX" 2>/dev/null | sed -n 's/^raw: *//p')"
    printf 'распознано: %s\n' "$RAW"
    # Ищем КАЖДОЕ слово длиннее пяти букв, а не одно случайное. Разбор на
    # python3: `tr` с классом [:alnum:] в системной локали не понимает кириллицу
    # и рвёт UTF-8 по байтам — из пяти русских слов уцелевало одно английское,
    # и проверка выглядела сильной, будучи почти пустой.
    JOURNAL_FILE="$WORK/journal.txt"
    /usr/bin/log show --predicate 'subsystem == "local.vox.Vox"' --last 5m > "$JOURNAL_FILE" 2>/dev/null || true
    RESULT="$(RAW_TEXT="$RAW" JOURNAL="$JOURNAL_FILE" python3 - <<'PYEOF'
import os, re, sys
raw = os.environ["RAW_TEXT"]
journal = open(os.environ["JOURNAL"], encoding="utf-8", errors="replace").read()
words = sorted({w for w in re.findall(r"\w+", raw, flags=re.UNICODE) if len(w) >= 6})
leaked = [w for w in words if w in journal]
print(len(words), ",".join(leaked))
PYEOF
)"
    COUNT="${RESULT%% *}"
    LEAKED="${RESULT#* }"
    printf 'слов-канареек: %s\n' "$COUNT"
    if [ "$COUNT" = "0" ]; then
        bad "не удалось выделить ни одного слова — проверка бессодержательна"
    elif [ -z "$LEAKED" ]; then
        ok "ни одно из $COUNT слов расшифровки в журнале не встречается"
    else
        bad "в журнале найдены слова расшифровки: $LEAKED"
    fi
else
    bad "нет fixture для проверки"
fi

hdr "5. После выхода процесс не остаётся"
# Гасим СТРОГО по PID своей копии из .build. Обращение по имени приложения
# («tell application "Vox" to quit») задело бы и установленную копию, если она
# запущена, — это чужой процесс для этой проверки.
open "$APP" 2>/dev/null || true
sleep 3
MYPID="$(pgrep -f "^$APP/Contents/MacOS/Vox$" | head -1)"
if [ -z "$MYPID" ]; then
    bad "копия из .build не запустилась, проверить нечего"
else
    printf 'гашу собственный процесс %s\n' "$MYPID"
    kill "$MYPID" 2>/dev/null || true
    sleep 3
    if kill -0 "$MYPID" 2>/dev/null; then bad "процесс $MYPID остался"; else ok "процесса не осталось"; fi
fi

hdr "6. Приложение не прописывается в автозапуск"
FOUND=""
for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    [ -d "$d" ] && FOUND="$FOUND$(grep -rl -i 'vox' "$d" 2>/dev/null || true)"
done
ITEMS="$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -ci vox || true)"
printf 'LaunchAgent/Daemon с упоминанием Vox: %s\n' "${FOUND:-нет}"
printf 'login items с Vox: %s\n' "$ITEMS"
if [ -z "$FOUND" ] && [ "$ITEMS" = "0" ]; then
    ok "ни LaunchAgent, ни login item"
else
    bad "нашлись записи автозапуска"
fi

rm -rf "$WORK"
printf '\n==================\nпройдено: %s, провалено: %s\n' "$PASS" "$FAIL"
[ "$FAIL" = "0" ]
