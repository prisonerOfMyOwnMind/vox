import Foundation
import VoxCore

/// Точка входа для headless-режима `--transcribe-file`.
/// `swift/Vox/main.swift` её только вызывает.
public enum STTEntry {
    /// Распознаёт файл локально и возвращает сырой текст.
    public static func transcribeFile(_ path: String) async throws -> String {
        let samples = try AudioFileReader.read(path: path)
        return try await Transcriber().transcribe(samples)
    }
}
