import Testing
import Foundation
import VoxCore
@testable import VoxClean

/// Подставной распознаватель: выдаёт заранее заданные строки по порядку вызовов.
/// Живая модель в ветке `clean` недоступна, runner проверяется на нём.
private actor StubTranscriber: Transcribing {
    private let replies: [String]
    private var index = 0
    private(set) var receivedDurations: [Double] = []

    init(replies: [String]) { self.replies = replies }

    func transcribe(_ samples: AudioSamples) async throws -> String {
        receivedDurations.append(samples.durationSeconds)
        defer { index += 1 }
        return index < replies.count ? replies[index] : ""
    }

    func durations() -> [Double] { receivedDurations }
}

private enum Layout {
    /// Корень worktree выводится от файла теста, чтобы прогон не зависел от cwd.
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // VoxTests
        .deletingLastPathComponent()  // tests
        .deletingLastPathComponent()  // корень

    static let fixturesDirectory = repositoryRoot.appendingPathComponent("fixtures")

    /// Копия набора во временном каталоге: прогон пишет отчёт рядом с manifest,
    /// а засорять рабочее дерево тесты не должны.
    static func stagedFixtures() throws -> URL {
        let staged = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vox-clean-regression-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixturesDirectory, to: staged)
        return staged
    }

    static func manifest(at directory: URL) throws -> FixtureManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }
}

@Suite("Набор fixtures")
struct CleanFixtureManifestTests {

    @Test("Manifest читается и все аудиофайлы на месте")
    func manifestResolves() throws {
        let manifest = try Layout.manifest(at: Layout.fixturesDirectory)
        #expect(!manifest.fixtures.isEmpty)
        for fixture in manifest.fixtures {
            let audio = Layout.fixturesDirectory.appendingPathComponent(fixture.audio)
            #expect(FileManager.default.fileExists(atPath: audio.path), "нет \(fixture.audio)")
            #expect(!fixture.expected.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @Test("Каждая запись помечена synthetic: записей владельца в наборе пока нет")
    func everyFixtureIsMarkedSynthetic() throws {
        for fixture in try Layout.manifest(at: Layout.fixturesDirectory).fixtures {
            #expect(fixture.tags.contains("synthetic"), "\(fixture.audio) без тега synthetic")
        }
    }

    @Test("Набор покрывает то, что должен проверять")
    func coverageTagsPresent() throws {
        let tags = Set(try Layout.manifest(at: Layout.fixturesDirectory)
            .fixtures.flatMap(\.tags))
        for required in ["russian", "terms", "filler", "self-correction", "repeat",
                         "enumeration", "injection"] {
            #expect(tags.contains(required), "нет покрытия для тега \(required)")
        }
    }

    @Test("Эталонные тексты устойчивы к нормализации")
    func expectedTextsAreNormalisationStable() throws {
        for fixture in try Layout.manifest(at: Layout.fixturesDirectory).fixtures {
            #expect(Normalizer().normalize(fixture.expected) == fixture.expected,
                    "нормализатор меняет эталон \(fixture.audio)")
        }
    }

    @Test("Аудио читается в контрактный формат: mono, 16 kHz, ненулевая длительность")
    func audioLoads() throws {
        for fixture in try Layout.manifest(at: Layout.fixturesDirectory).fixtures {
            let audio = Layout.fixturesDirectory.appendingPathComponent(fixture.audio)
            let samples = try WaveFile.read(at: audio)
            #expect(samples.values.count > 0, "пустое аудио \(fixture.audio)")
            #expect(samples.durationSeconds > 0.5, "слишком короткое \(fixture.audio)")
        }
    }
}

@Suite("Runner regression")
struct CleanRegressionRunnerTests {

    @Test("Отчёт по известной паре: обработка убирает ошибки, которые есть в сыром тексте")
    func knownNumbersEndToEnd() async throws {
        let staged = try Layout.stagedFixtures()
        defer { try? FileManager.default.removeItem(at: staged) }

        // Свой manifest на одном настоящем файле: числа в отчёте посчитаны вручную.
        let manifest = FixtureManifest(fixtures: [
            FixtureEntry(audio: "audio/dev-02.wav",
                         expected: "Поднимаем Docker",
                         tags: ["synthetic", "terms"])
        ])
        let manifestURL = staged.appendingPathComponent("one.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let reportPath = try await CleanEntry.runRegression(
            manifestPath: manifestURL.path,
            transcriber: StubTranscriber(replies: ["  поднимаем   докер докер  "]),
            normalizer: Normalizer()
        )

        let report = try JSONDecoder().decode(
            RegressionReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))
        #expect(report.records.count == 1)
        let record = try #require(report.records.first)
        #expect(record.raw == "  поднимаем   докер докер  ")
        #expect(record.normalized == "поднимаем Docker")
        // эталон 2 слова; обработанный текст совпадает полностью
        #expect(record.wer == 0.0)
        // сырой текст: 1 замена (докер → docker) и 1 вставка на 2 слова эталона
        #expect(record.werRaw == 1.0)
        #expect(report.meanWER == 0.0)
        #expect(report.meanWERRaw == 1.0)
    }

    @Test("Отчёт ложится рядом с manifest, имя несёт версию словаря")
    func reportLandsNextToManifest() async throws {
        let staged = try Layout.stagedFixtures()
        defer { try? FileManager.default.removeItem(at: staged) }
        let manifestURL = staged.appendingPathComponent("manifest.json")

        let reportPath = try await CleanEntry.runRegression(
            manifestPath: manifestURL.path,
            transcriber: StubTranscriber(replies: []),
            normalizer: Normalizer()
        )
        let reportURL = URL(fileURLWithPath: reportPath)
        #expect(reportURL.deletingLastPathComponent().path == staged.path)
        #expect(reportURL.lastPathComponent.hasPrefix("regression-"))
        #expect(reportURL.lastPathComponent.hasSuffix("-\(Normalizer.dictionaryVersion).json"))
    }

    @Test("Все поля отчёта заполнены фактическими значениями из Pins")
    func reportCarriesPins() async throws {
        let staged = try Layout.stagedFixtures()
        defer { try? FileManager.default.removeItem(at: staged) }
        let manifestURL = staged.appendingPathComponent("manifest.json")
        let manifest = try Layout.manifest(at: staged)

        let reportPath = try await CleanEntry.runRegression(
            manifestPath: manifestURL.path,
            transcriber: StubTranscriber(replies: manifest.fixtures.map(\.expected)),
            normalizer: Normalizer()
        )
        let report = try JSONDecoder().decode(
            RegressionReport.self, from: Data(contentsOf: URL(fileURLWithPath: reportPath)))

        #expect(report.appVersion == Pins.appVersion)
        #expect(report.fluidAudioCommit == Pins.fluidAudioCommit)
        #expect(report.modelRepo == Pins.modelRepo)
        #expect(report.modelRevision == Pins.modelRevision)
        #expect(report.startedAt.hasSuffix("Z"))
        #expect(report.totalRuntimeSeconds >= 0)
        #expect(report.records.count == manifest.fixtures.count)

        // Распознаватель вернул эталон дословно, значит ошибок быть не должно.
        #expect(report.meanWER == 0.0)
        #expect(report.meanWERRaw == 0.0)
        for (record, fixture) in zip(report.records, manifest.fixtures) {
            #expect(record.audio == fixture.audio)
            #expect(record.tags == fixture.tags)
            #expect(record.expected == fixture.expected)
            #expect(record.wer == 0.0)
            #expect(record.transcribeSeconds >= 0)
        }
    }

    @Test("Пустой и битый manifest останавливают прогон понятной ошибкой")
    func badManifestsFail() async throws {
        let staged = try Layout.stagedFixtures()
        defer { try? FileManager.default.removeItem(at: staged) }

        let empty = staged.appendingPathComponent("empty.json")
        try Data(#"{"fixtures":[]}"#.utf8).write(to: empty)
        await #expect(throws: RegressionError.self) {
            _ = try await CleanEntry.runRegression(
                manifestPath: empty.path,
                transcriber: StubTranscriber(replies: []),
                normalizer: Normalizer())
        }

        let broken = staged.appendingPathComponent("broken.json")
        try Data("не json".utf8).write(to: broken)
        await #expect(throws: RegressionError.self) {
            _ = try await CleanEntry.runRegression(
                manifestPath: broken.path,
                transcriber: StubTranscriber(replies: []),
                normalizer: Normalizer())
        }

        await #expect(throws: RegressionError.self) {
            _ = try await CleanEntry.runRegression(
                manifestPath: staged.appendingPathComponent("нет-такого.json").path,
                transcriber: StubTranscriber(replies: []),
                normalizer: Normalizer())
        }
    }

    @Test("Отсутствующее аудио останавливает прогон, а не пропускается молча")
    func missingAudioFails() async throws {
        let staged = try Layout.stagedFixtures()
        defer { try? FileManager.default.removeItem(at: staged) }

        let manifest = FixtureManifest(fixtures: [
            FixtureEntry(audio: "audio/нет-такого.wav", expected: "что-то", tags: ["synthetic"])
        ])
        let manifestURL = staged.appendingPathComponent("missing.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        await #expect(throws: RegressionError.self) {
            _ = try await CleanEntry.runRegression(
                manifestPath: manifestURL.path,
                transcriber: StubTranscriber(replies: []),
                normalizer: Normalizer())
        }
    }
}

@Suite("Чтение WAV")
struct CleanWaveFileTests {

    @Test("Не-WAV отвергается с указанием требуемого формата")
    func rejectsNonWave() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("vox-not-a-wave-\(UUID().uuidString).wav")
        try Data("это не аудио".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: RegressionError.self) { _ = try WaveFile.read(at: file) }
    }

    @Test("Длительность синтетической записи совпадает с числом отсчётов")
    func durationMatchesSampleCount() throws {
        let audio = Layout.fixturesDirectory.appendingPathComponent("audio/dev-01.wav")
        let samples = try WaveFile.read(at: audio)
        #expect(samples.durationSeconds == Double(samples.values.count) / 16_000)
    }
}
