import Testing
import Foundation
@testable import VoxCore
@testable import VoxSTT

@Suite("Контракты VoxCore")
struct CoreContractsTests {

    @Test("Закреплённые ревизии выглядят как полные git-хеши")
    func pinsAreFullHashes() {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        for hash in [Pins.fluidAudioCommit, Pins.modelRevision] {
            #expect(hash.count == 40)
            #expect(CharacterSet(charactersIn: hash).isSubset(of: hex))
        }
    }

    @Test("Состав состояний закрыт контрактом")
    func appStatesAreFixed() {
        #expect(AppState.allCases.count == 6)
        #expect(AppState.needsPermissions.rawValue == "needs permissions")
    }

    @Test("Длительность считается по контрактной частоте 16 kHz")
    func durationUsesContractSampleRate() {
        let samples = AudioSamples(values: Array(repeating: 0, count: 32_000))
        #expect(samples.durationSeconds == 2.0)
    }

    @Test("Manifest модели переживает round-trip через JSON")
    func manifestRoundTrip() throws {
        let manifest = ModelManifest(
            modelRepo: Pins.modelRepo,
            modelRevision: Pins.modelRevision,
            generatedAt: "2026-09-03T00:00:00Z",
            entries: [
                .init(
                    path: "Decoder.mlmodelc/coremldata.bin", sizeBytes: 554,
                    sha256: String(repeating: "a", count: 64))
            ]
        )
        let data = try JSONEncoder().encode(manifest)
        #expect(try JSONDecoder().decode(ModelManifest.self, from: data) == manifest)
    }

    @Test("Путь модели в сборке и в runtime — один и тот же")
    func modelPathAgreesBetweenBuildAndRuntime() {
        // scripts/build-app.sh кладёт модель по Pins, VoxSTT ищет её по ModelLocation.
        // Разойдутся — собранный .app не найдёт модель, а тесты этого не заметят.
        #expect(Pins.modelBundleSubpath == ModelLocation.bundleSubpath)
    }
}
