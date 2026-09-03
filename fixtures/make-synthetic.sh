#!/bin/bash
# Собирает синтетический набор fixtures командой `say`. Сеть не нужна.
#
# ЭТО НЕ ЗАПИСИ ВЛАДЕЛЬЦА. Синтезатор даёт тепличные условия: идеальную
# артикуляцию, ровный темп, ни комнаты, ни микрофона, ни настоящих оговорок.
# Каждая запись помечена тегом `synthetic`, и тест падает, если пометка исчезнет.
# Требование задания «финальный набор — записи владельца» этим набором НЕ
# закрывается; он существует, чтобы regression гонялся на осмысленном объёме.
#
# У каждой записи два текста: произносимый (с паразитами и оговорками) и
# ожидаемый (чистый). Разница между ними — то, что должна вычищать обработка.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/fixtures/audio"
mkdir -p "$OUT"
rm -f "$OUT"/dev-*.wav

python3 "$ROOT/fixtures/synthetic-set.py" --emit-spoken | while IFS='|' read -r name voice text; do
    say -v "$voice" -o "$OUT/$name.wav" --file-format=WAVE --data-format=LEF32@16000 "$text"
    printf '%s ' "$name"
done
printf '\n'

python3 "$ROOT/fixtures/synthetic-set.py" --emit-manifest > "$ROOT/fixtures/manifest.json"
printf 'манифест: %s\n' "$ROOT/fixtures/manifest.json"
