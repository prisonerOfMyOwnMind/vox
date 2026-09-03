import Foundation

/// Аудио в памяти процесса. Единственная форма, в которой запись доходит до распознавания.
/// Контракт: mono, 16 kHz, Float32. Файлы на диск не пишутся.
public struct AudioSamples: Sendable {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1

    public let values: [Float]

    public init(values: [Float]) {
        self.values = values
    }

    public var durationSeconds: Double {
        Double(values.count) / Self.sampleRate
    }
}

/// Результат полного прохода: сырая расшифровка и её детерминированная обработка.
/// raw хранится отдельно, чтобы regression мог сравнить две версии.
public struct Transcript: Sendable, Equatable {
    public let raw: String
    public let normalized: String

    public init(raw: String, normalized: String) {
        self.raw = raw
        self.normalized = normalized
    }
}

/// Реализует VoxSTT. Одна операция за раз обеспечивается тем, что реализация — actor.
public protocol Transcribing: Sendable {
    func transcribe(_ samples: AudioSamples) async throws -> String
}

/// Реализует VoxClean. Чистая функция: одинаковый вход даёт одинаковый выход.
/// Нет уверенности в преобразовании — возвращается исходный текст.
public protocol Normalizing: Sendable {
    func normalize(_ raw: String) -> String
}

public enum VoxError: Error, LocalizedError, Sendable {
    case notImplemented(String)
    case recordingTooShort(seconds: Double, minimum: Double)
    case modelMissing(String)
    case modelCorrupted(String)
    case transcriptionBusy
    case transcriptionFailed(String)
    case permissionDenied(String)
    case pasteFailed(String)
    case networkLockdownFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let what):
            return "Не реализовано: \(what)"
        case .recordingTooShort(let seconds, let minimum):
            return String(format: "Запись слишком короткая: %.2f с при минимуме %.2f с", seconds, minimum)
        case .modelMissing(let detail):
            return "Модель отсутствует: \(detail). Переустановите проверенную сборку."
        case .modelCorrupted(let detail):
            return "Модель изменена или повреждена: \(detail). Переустановите проверенную сборку."
        case .transcriptionBusy:
            return "Распознавание уже идёт"
        case .transcriptionFailed(let detail):
            return "Распознавание не удалось: \(detail)"
        case .permissionDenied(let what):
            return "Нет разрешения: \(what)"
        case .pasteFailed(let detail):
            return "Не удалось вставить текст: \(detail)"
        case .networkLockdownFailed(let detail):
            return "Не удалось запретить исходящую сеть: \(detail)"
        }
    }
}
