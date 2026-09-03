import Foundation
import VoxCore

/// ЗАГЛУШКА bootstrap. Реализация — ветка `stt`.
/// Actor, а не собственные блокировки: одновременно допустима одна операция.
public actor Transcriber: Transcribing {
    public init() {}

    public func transcribe(_ samples: AudioSamples) async throws -> String {
        throw VoxError.notImplemented("VoxSTT.Transcriber.transcribe")
    }
}

public enum STTSelfTest {
    /// Ветка `stt` добавляет сюда: проверку manifest модели и загрузку встроенной
    /// модели в offline-режиме.
    public static func cases() -> [SelfTestCase] { [] }
}
