# Контракты проекта

Файл фиксирует границы между ветками. Субагент, работающий в своём worktree,
меняет только файлы своей строки таблицы. Общие файлы заморожены: их правит
главный агент по явному решению владельца.

## Границы файлов

| Ветка | Может менять | Не трогает |
|---|---|---|
| `stt` | `swift/VoxSTT/**`, `scripts/fetch-model.sh`, `tests/VoxTests/STT*.swift` | всё остальное |
| `clean` | `swift/VoxClean/**`, `workflows/regression.md`, `fixtures/**`, `tests/VoxTests/Clean*.swift` | всё остальное |
| `deliver` | `swift/VoxApp/**`, `scripts/build-app.sh`, `Resources/**`, `tests/VoxTests/App*.swift` | всё остальное |
| заморожено | `swift/VoxCore/**`, `swift/Vox/**`, `Package.swift`, `CONTRACTS.md`, `README.md`, `.gitignore` | правит только главный агент |

Имена тестовых файлов разведены по префиксам, чтобы три ветки не конфликтовали
в одном каталоге.

## Модули

`VoxCore` — типы и протоколы, без зависимостей. Единственный источник правды по
закреплённым ревизиям (`Pins`), состояниям (`AppState`), форматам результатов
(`SelfTest`, `Regression`, `ModelManifest`).

`VoxSTT` — зависит от `VoxCore` и `FluidAudio`. Реализует `Transcribing` актором.
Отвечает за целостность модели и загрузку из bundle без сети.

`VoxClean` — зависит от `VoxCore`. Реализует `Normalizing` чистой функцией.
Отвечает за WER и regression runner.

`VoxApp` — зависит от `VoxCore`, `VoxSTT`, `VoxClean`. Menu bar, разрешения,
hotkey, запись, индикатор, буфер обмена, запрет исходящей сети.

`Vox` — исполняемый файл. Только разбор аргументов и порядок запуска.

## Точки сборки

Каждый модуль отдаёт свои случаи служебных проверок через
`STTSelfTest.cases()`, `CleanSelfTest.cases()`, `AppSelfTest.cases()`.
`swift/Vox/main.swift` их только складывает, поэтому три ветки наполняют
`--self-test` независимо и не конфликтуют.

Так же устроены headless-режимы. `main.swift` заморожен и уже вызывает
`STTEntry.transcribeFile(_:)` и `CleanEntry.runRegression(manifestPath:transcriber:normalizer:)`.
Ветки заполняют тела этих функций в своих модулях и не касаются исполняемого
таргета. Сигнатуры менять нельзя: их знают три ветки сразу.

## Порядок запуска процесса

Зафиксирован в `swift/Vox/main.swift` и не меняется:

1. `Bootstrap.activateNetworkLockdown()`;
2. разбор аргументов;
3. app delegate, загрузка модели, любое обращение к FluidAudio.

`activateNetworkLockdown` либо возвращает `.applied` с названием механизма, либо
бросает `VoxError.networkLockdownFailed` и процесс завершается. Механизм печатается
в stderr при старте — это доказательство изоляции, а не отладочный вывод.

## Аудио

Единственная форма передачи: `AudioSamples` — mono, 16 kHz, Float32, в памяти
процесса. Временные аудиофайлы, кэш диктовок и журнал восстановления запрещены.

## Закреплённые ревизии

| Что | Значение |
|---|---|
| FluidAudio | `v0.15.6`, commit `4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b` |
| Репозиторий модели | `FluidInference/parakeet-tdt-0.6b-v3-coreml` |
| Ревизия модели | `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe` |

Разведка FluidAudio v0.15.6, на которую опираются контракты:

- `AsrModels.load(from:)` отделён от `AsrModels.download(...)`, поэтому путь
  скачивания в runtime просто не вызывается;
- для v3 требуются `Preprocessor.mlmodelc`, `Encoder.mlmodelc`, `Decoder.mlmodelc`,
  `JointDecisionv3.mlmodelc` и `parakeet_vocab.json` — около 483 МБ из 3.59 ГБ
  репозитория модели. Остальные файлы в bundle не идут;
- `AsrModels.repoPath` берёт родителя переданного каталога и приписывает
  `Repo.folderName`, а тот ОТБРАСЫВАЕТ суффикс `-coreml`. Каталог модели поэтому
  называется `parakeet-tdt-0.6b-v3`, а не как репозиторий. Проверено эмпирически
  веткой `stt`; ошибочная догадка обратного стоила проекту несобираемого `.app`.
  Значение живёт в `Pins.modelBundleSubpath` и `ModelLocation.bundleSubpath`,
  их равенство стережёт `CoreContractsTests`.
