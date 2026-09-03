import Foundation
import VoxCore

/// Точка входа для headless-режима `--transcribe-file`.
/// Заполняет ветка `stt`; `swift/Vox/main.swift` её только вызывает.
public enum STTEntry {
    /// Распознаёт файл локально и возвращает сырой текст.
    public static func transcribeFile(_ path: String) async throws -> String {
        throw VoxError.notImplemented("VoxSTT.STTEntry.transcribeFile")
    }
}
