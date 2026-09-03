import Foundation
import VoxCore

/// ЗАГЛУШКА bootstrap. Реализация — ветка `clean`.
/// Обработка детерминированная и консервативная: нет уверенности — возвращается вход.
public struct Normalizer: Normalizing {
    public init() {}

    public func normalize(_ raw: String) -> String { raw }
}

public enum CleanSelfTest {
    /// Ветка `clean` добавляет сюда проверки нормализатора и WER.
    public static func cases() -> [SelfTestCase] { [] }
}
