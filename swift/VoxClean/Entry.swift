import Foundation
import VoxCore

/// Точка входа для `--regression`.
/// Заполняет ветка `clean`; `swift/Vox/main.swift` её только вызывает.
public enum CleanEntry {

    /// Прогоняет manifest, пишет отчёт рядом с ним и возвращает путь к отчёту.
    /// Распознаватель передаётся снаружи, чтобы модуль не зависел от VoxSTT.
    ///
    /// Пути аудио берутся относительно каталога manifest. Порядок записей
    /// в отчёте повторяет порядок в manifest.
    public static func runRegression(
        manifestPath: String,
        transcriber: any Transcribing,
        normalizer: any Normalizing
    ) async throws -> String {
        let manifestURL = URL(fileURLWithPath: manifestPath).standardizedFileURL
        let baseDirectory = manifestURL.deletingLastPathComponent()

        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw RegressionError.manifestUnreadable(
                path: manifestURL.path, detail: "файл не открывается")
        }
        let manifest: FixtureManifest
        do {
            manifest = try JSONDecoder().decode(FixtureManifest.self, from: manifestData)
        } catch {
            throw RegressionError.manifestUnreadable(
                path: manifestURL.path, detail: "\(error)")
        }
        guard !manifest.fixtures.isEmpty else {
            throw RegressionError.manifestEmpty(path: manifestURL.path)
        }

        let startedAt = Date()
        let clock = ContinuousClock()
        let runStart = clock.now

        var records: [RegressionRecord] = []
        records.reserveCapacity(manifest.fixtures.count)

        for fixture in manifest.fixtures {
            let audioURL = URL(fileURLWithPath: fixture.audio, relativeTo: baseDirectory)
                .standardizedFileURL
            let samples = try WaveFile.read(at: audioURL)

            let transcribeStart = clock.now
            let raw = try await transcriber.transcribe(samples)
            let transcribeSeconds = seconds(clock.now - transcribeStart)

            let normalized = normalizer.normalize(raw)
            records.append(
                RegressionRecord(
                    audio: fixture.audio,
                    tags: fixture.tags,
                    expected: fixture.expected,
                    raw: raw,
                    normalized: normalized,
                    wer: WordErrorRate.rate(reference: fixture.expected, hypothesis: normalized),
                    werRaw: WordErrorRate.rate(reference: fixture.expected, hypothesis: raw),
                    transcribeSeconds: transcribeSeconds
                )
            )
        }

        let report = RegressionReport(
            startedAt: iso8601(startedAt),
            totalRuntimeSeconds: seconds(clock.now - runStart),
            appVersion: Pins.appVersion,
            fluidAudioCommit: Pins.fluidAudioCommit,
            modelRepo: Pins.modelRepo,
            modelRevision: Pins.modelRevision,
            dictionaryVersion: Normalizer.dictionaryVersion,
            meanWER: mean(records.map(\.wer)),
            meanWERRaw: mean(records.map(\.werRaw)),
            records: records
        )

        let reportURL = baseDirectory.appendingPathComponent(reportFileName(at: startedAt))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(report).write(to: reportURL, options: .atomic)
        } catch {
            throw RegressionError.reportNotWritten(path: reportURL.path, detail: "\(error)")
        }
        return reportURL.path
    }

    /// Версия словаря входит в имя: отчёты, снятые разными таблицами правил,
    /// между собой не сравнимы, а в `RegressionReport` поля под неё нет.
    static func reportFileName(at date: Date) -> String {
        "regression-\(compactStamp(date))-\(Normalizer.dictionaryVersion).json"
    }

    // MARK: - Мелочи

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    /// Метка времени для имени файла отчёта.
    /// Без принудительных развёрток: падение при сохранении отчёта обесценило бы
    /// весь прогон, а он к этому моменту уже отработал.
    private static func compactStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) { calendar.timeZone = utc }
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}
