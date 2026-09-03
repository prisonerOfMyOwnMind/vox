import Foundation
import VoxCore

/// Точка входа для `--regression`.
/// Заполняет ветка `clean`; `swift/Vox/main.swift` её только вызывает.
public enum CleanEntry {
    /// Прогоняет manifest, пишет отчёт рядом с ним и возвращает путь к отчёту.
    /// Распознаватель передаётся снаружи, чтобы модуль не зависел от VoxSTT.
    public static func runRegression(
        manifestPath: String,
        transcriber: any Transcribing,
        normalizer: any Normalizing
    ) async throws -> String {
        throw VoxError.notImplemented("VoxClean.CleanEntry.runRegression")
    }
}
