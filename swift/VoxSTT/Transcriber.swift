import FluidAudio
import Foundation
import VoxCore

/// Actor, а не собственные блокировки: одновременно допустима одна операция.
/// Модель загружается один раз на актор и остаётся в памяти.
public actor Transcriber: Transcribing {
    private var manager: AsrManager?

    public init() {}

    public func transcribe(_ samples: AudioSamples) async throws -> String {
        let manager = try await preparedManager()
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples.values, decoderState: &decoderState)
        return result.text
    }

    private func preparedManager() async throws -> AsrManager {
        if let manager {
            return manager
        }
        let models = try await Self.loadVerifiedModels(directory: ModelLocation.modelDirectory())
        let created = AsrManager()
        try await created.loadModels(models)
        manager = created
        return created
    }

    /// Проверка целостности до загрузки и загрузка строго с диска.
    /// `AsrModels.download`, `downloadAndLoad` и `loadWithAutoRecovery` не вызываются;
    /// `ModelHub.offlineMode` дополнительно закрывает путь докачки внутри FluidAudio,
    /// включая его же попытку стереть каталог и скачать заново после неудачной загрузки.
    static func loadVerifiedModels(directory: URL) async throws -> AsrModels {
        try ModelIntegrity.verify(directory: directory)
        ModelHub.offlineMode = true
        return try await AsrModels.load(from: directory)
    }
}
