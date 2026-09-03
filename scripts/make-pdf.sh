#!/bin/bash
# Собирает PDF из REPORT.md и отрисовывает страницы в картинки для проверки глазами.
#
# Печатает Chrome в headless-режиме с --no-pdf-header-footer: по умолчанию он
# ставит колонтитул с локальным путём к файлу, а в публичный документ путь с
# именем пользователя попадать не должен. Номера страниц проставляет
# scripts/pdf-finish.swift, он же растеризует страницы.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/REPORT.md}"
NAME="$(basename "${SRC%.md}" | tr '[:upper:]' '[:lower:]')"
OUT="$ROOT/docs/vox-$NAME.pdf"
PAGES="$ROOT/.build/pdf-pages"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

die() { printf 'ОСТАНОВ: %s\n' "$1" >&2; exit 1; }

[ -f "$SRC" ] || die "нет исходника $SRC"
[ -x "$CHROME" ] || die "нет Chrome для печати: $CHROME"

mkdir -p "$ROOT/docs"
rm -rf "$PAGES"; mkdir -p "$PAGES"

HTML="$(mktemp -t vox-report).html"
python3 "$ROOT/scripts/md-to-html.py" "$SRC" > "$HTML" || die "разметка не собралась в HTML"

# Три исхода различаются: маркеры разметки, дожившие до HTML, — это дефект
# конвертера, а не «ничего не найдено».
if grep -q '\*\*' "$HTML"; then
    die "в HTML остались маркеры разметки ** — конвертер не разобрал жирный текст"
fi

"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
    --print-to-pdf="$HTML.pdf" "$HTML" >/dev/null 2>&1 || die "Chrome не напечатал PDF"

swift "$ROOT/scripts/pdf-finish.swift" "$HTML.pdf" "$OUT" "$PAGES" || die "не удалось проставить номера страниц"
rm -f "$HTML" "$HTML.pdf"

printf 'готово: %s\n' "$OUT"
printf 'страницы для проверки глазами: %s\n' "$PAGES"
