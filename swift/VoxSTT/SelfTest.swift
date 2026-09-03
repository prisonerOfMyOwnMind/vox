import FluidAudio
import Foundation
import VoxCore

public enum STTSelfTest {
    public static func cases() -> [SelfTestCase] {
        [
            SelfTestCase(name: "manifest модели сходится с каталогом") {
                do {
                    try ModelIntegrity.verify(directory: ModelLocation.modelDirectory())
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
            SelfTestCase(name: "подделанный байт в файле модели ловится") {
                await tamperedByteIsCaught()
            },
            SelfTestCase(name: "модель грузится без сети") {
                do {
                    let models = try await Transcriber.loadVerifiedModels(
                        directory: ModelLocation.modelDirectory())
                    guard ModelHub.offlineMode else {
                        return "загрузка прошла, но offlineMode не включён"
                    }
                    guard models.encoder != nil else {
                        return "загружено без энкодера"
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            },
        ]
    }

    /// Работает на временной копии каталога: рабочий каталог модели не меняется.
    private static func tamperedByteIsCaught() async -> String? {
        let fileManager = FileManager.default
        let copy = fileManager.temporaryDirectory
            .appendingPathComponent("vox-stt-tamper-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: copy) }

        do {
            try fileManager.copyItem(at: ModelLocation.modelDirectory(), to: copy)

            let manifest = try ModelIntegrity.readManifest(directory: copy)
            guard let entry = manifest.entries.min(by: { $0.sizeBytes < $1.sizeBytes }) else {
                return "manifest копии пуст"
            }
            let target = copy.appendingPathComponent(entry.path)
            var bytes = try Data(contentsOf: target)
            guard !bytes.isEmpty else {
                return "файл \(entry.path) пуст, подделывать нечего"
            }
            bytes[bytes.startIndex] ^= 0xFF
            try bytes.write(to: target)

            try ModelIntegrity.verify(directory: copy)
            return "подделанный байт в \(entry.path) не обнаружен"
        } catch VoxError.modelCorrupted {
            return nil
        } catch {
            return "ожидался modelCorrupted, получено: \(error.localizedDescription)"
        }
    }
}
