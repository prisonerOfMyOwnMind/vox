import Foundation

/// Одна запись в manifest набора fixtures.
public struct FixtureEntry: Codable, Sendable, Equatable {
    /// Путь к аудио относительно каталога manifest.
    public let audio: String
    /// Ожидаемый текст, записанный владельцем при подготовке набора.
    public let expected: String
    /// Свободные метки: injection, filler, terms, enumeration и подобные.
    public let tags: [String]

    public init(audio: String, expected: String, tags: [String]) {
        self.audio = audio
        self.expected = expected
        self.tags = tags
    }
}

public struct FixtureManifest: Codable, Sendable, Equatable {
    public let fixtures: [FixtureEntry]

    public init(fixtures: [FixtureEntry]) {
        self.fixtures = fixtures
    }
}

/// Результат по одному fixture. Состав полей задан контрактом проекта.
public struct RegressionRecord: Codable, Sendable, Equatable {
    public let audio: String
    public let tags: [String]
    public let expected: String
    public let raw: String
    public let normalized: String
    /// Доля ошибочных слов относительно ожидаемого текста, посчитана по normalized.
    public let wer: Double
    public let werRaw: Double
    public let transcribeSeconds: Double

    public init(
        audio: String, tags: [String], expected: String, raw: String, normalized: String,
        wer: Double, werRaw: Double, transcribeSeconds: Double
    ) {
        self.audio = audio
        self.tags = tags
        self.expected = expected
        self.raw = raw
        self.normalized = normalized
        self.wer = wer
        self.werRaw = werRaw
        self.transcribeSeconds = transcribeSeconds
    }
}

public struct RegressionReport: Codable, Sendable, Equatable {
    public let startedAt: String
    public let totalRuntimeSeconds: Double
    public let appVersion: String
    public let fluidAudioCommit: String
    public let modelRepo: String
    public let modelRevision: String
    public let meanWER: Double
    public let meanWERRaw: Double
    public let records: [RegressionRecord]

    public init(
        startedAt: String, totalRuntimeSeconds: Double, appVersion: String,
        fluidAudioCommit: String, modelRepo: String, modelRevision: String,
        meanWER: Double, meanWERRaw: Double, records: [RegressionRecord]
    ) {
        self.startedAt = startedAt
        self.totalRuntimeSeconds = totalRuntimeSeconds
        self.appVersion = appVersion
        self.fluidAudioCommit = fluidAudioCommit
        self.modelRepo = modelRepo
        self.modelRevision = modelRevision
        self.meanWER = meanWER
        self.meanWERRaw = meanWERRaw
        self.records = records
    }
}
