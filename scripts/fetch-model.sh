#!/bin/bash
# Контролируемая сборочная загрузка модели распознавания.
#
# Качает ровно те файлы, что перечислены в scripts/model-files.txt, с
# закреплённой ревизии репозитория модели. Список в репозитории — источник
# правды: он задаёт и состав загрузки, и ожидаемые SHA-256. Сеть не может
# добавить файл, которого в списке нет.
#
# Коды выхода: 0 — всё сошлось, 1 — расхождение с ожидаемым, 3 — сломался
# инструмент (curl, shasum, find, stat), то есть проверка не состоялась.
set -euo pipefail

REPO="FluidInference/parakeet-tdt-0.6b-v3-coreml"
REVISION="7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"
# Имя каталога задаёт FluidAudio: AsrModels.load(from:) ищет модель в
# <родитель>/<Repo.folderName>, а folderName для parakeetV3 — имя репозитория
# без суффикса `-coreml`. Каталог с `-coreml` загрузчик не находит.
FOLDER="parakeet-tdt-0.6b-v3"
MANIFEST_NAME="vox-model-manifest.json"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIST="$ROOT/scripts/model-files.txt"
DEST="$ROOT/models/$FOLDER"

fail() {
    printf 'ОСТАНОВ: %s\n' "$1" >&2
    exit 1
}

broken() {
    printf 'ОСТАНОВ: инструмент сломался: %s\n' "$1" >&2
    exit 3
}

# Результат кладётся в глобальную переменную, а не в stdout: подстановка
# $(...) — подоболочка, и выход из неё по broken() потерял бы код 3.
SHA256_OUT=""
compute_sha256() {
    local file="$1" out status
    status=0
    out=$(/usr/bin/shasum -a 256 "$file") || status=$?
    if [ "$status" -ne 0 ]; then
        broken "shasum -a 256 '$file' вернул код $status"
    fi
    out=${out%% *}
    if [ ${#out} -ne 64 ]; then
        broken "shasum -a 256 '$file' вернул не хеш: '$out'"
    fi
    SHA256_OUT="$out"
}

SIZE_OUT=""
compute_size() {
    local file="$1" out status
    status=0
    out=$(/usr/bin/stat -f '%z' "$file") || status=$?
    if [ "$status" -ne 0 ]; then
        broken "stat -f %z '$file' вернул код $status"
    fi
    case "$out" in
        ''|*[!0-9]*) broken "stat -f %z '$file' вернул не число: '$out'" ;;
    esac
    SIZE_OUT="$out"
}

[ -f "$LIST" ] || fail "нет списка ожидаемых файлов $LIST"

# --- разбор списка -----------------------------------------------------------

expected_paths=()
expected_sums=()

while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    sum=${line%% *}
    path=${line#* }
    path=${path# }
    if [ ${#sum} -ne 64 ]; then
        fail "строка списка без 64-символьного SHA-256: '$line'"
    fi
    case "$sum" in
        *[!0-9a-f]*) fail "SHA-256 не в нижнем регистре или не hex: '$sum'" ;;
    esac
    if [ -z "$path" ]; then
        fail "строка списка без пути: '$line'"
    fi
    case "$path" in
        /*|*..*) fail "недопустимый путь в списке: '$path'" ;;
    esac
    if [ "$path" = "$MANIFEST_NAME" ]; then
        fail "manifest '$MANIFEST_NAME' не может быть элементом списка"
    fi
    expected_paths+=("$path")
    expected_sums+=("$sum")
done < "$LIST"

total=${#expected_paths[@]}
[ "$total" -gt 0 ] || fail "список $LIST пуст"

echo "репозиторий: $REPO"
echo "ревизия:     $REVISION"
echo "каталог:     $DEST"
echo "файлов:      $total"
echo ""

mkdir -p "$DEST"

# --- загрузка и сверка -------------------------------------------------------

downloaded=0
kept=0
index=0
while [ "$index" -lt "$total" ]; do
    path="${expected_paths[$index]}"
    want="${expected_sums[$index]}"
    file="$DEST/$path"
    index=$((index + 1))

    if [ -L "$file" ]; then
        fail "'$path' — symlink, такой файл не принимается"
    fi

    if [ -f "$file" ]; then
        compute_sha256 "$file"
        if [ "$SHA256_OUT" = "$want" ]; then
            kept=$((kept + 1))
            continue
        fi
    fi

    mkdir -p "$(dirname "$file")"
    rm -f "$file" "$file.partial"
    url="https://huggingface.co/$REPO/resolve/$REVISION/$path"
    status=0
    /usr/bin/curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$file.partial" || status=$?
    if [ "$status" -ne 0 ]; then
        rm -f "$file.partial"
        broken "curl '$url' вернул код $status"
    fi
    mv "$file.partial" "$file"
    downloaded=$((downloaded + 1))

    compute_sha256 "$file"
    if [ "$SHA256_OUT" != "$want" ]; then
        fail "SHA-256 не совпал для '$path': ожидался $want, получен $SHA256_OUT"
    fi
    echo "загружен $path"
done

echo ""
echo "загружено: $downloaded, уже совпадало: $kept"

# --- лишнее в каталоге -------------------------------------------------------

status=0
strays=$(/usr/bin/find "$DEST" ! -type f ! -type d -print) || status=$?
if [ "$status" -ne 0 ]; then
    broken "find по symlink и спецфайлам вернул код $status"
fi
if [ -n "$strays" ]; then
    fail "в каталоге модели есть symlink или спецфайлы:
$strays"
fi

status=0
actual=$(/usr/bin/find "$DEST" -type f -print) || status=$?
if [ "$status" -ne 0 ]; then
    broken "find по обычным файлам вернул код $status"
fi

allowed=$'\n'"$MANIFEST_NAME"$'\n'
index=0
while [ "$index" -lt "$total" ]; do
    allowed="$allowed${expected_paths[$index]}"$'\n'
    index=$((index + 1))
done

unexpected=""
while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel="${file#"$DEST"/}"
    case "$allowed" in
        *$'\n'"$rel"$'\n'*) ;;
        *) unexpected="$unexpected$rel"$'\n' ;;
    esac
done <<< "$actual"

if [ -n "$unexpected" ]; then
    fail "в каталоге модели есть неожиданные файлы:
$unexpected"
fi

# --- manifest ----------------------------------------------------------------

generated_at=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) || broken "date вернул ненулевой код"

manifest="$DEST/$MANIFEST_NAME"
{
    printf '{\n'
    printf '  "modelRepo": "%s",\n' "$REPO"
    printf '  "modelRevision": "%s",\n' "$REVISION"
    printf '  "generatedAt": "%s",\n' "$generated_at"
    printf '  "entries": [\n'
    index=0
    while [ "$index" -lt "$total" ]; do
        path="${expected_paths[$index]}"
        sum="${expected_sums[$index]}"
        compute_size "$DEST/$path"
        sep=","
        if [ "$index" -eq $((total - 1)) ]; then
            sep=""
        fi
        printf '    { "path": "%s", "sizeBytes": %s, "sha256": "%s" }%s\n' "$path" "$SIZE_OUT" "$sum" "$sep"
        index=$((index + 1))
    done
    printf '  ]\n'
    printf '}\n'
} > "$manifest.partial"
mv "$manifest.partial" "$manifest"

echo "manifest:  $manifest"
echo "готово: $total файлов сошлись с $LIST"
