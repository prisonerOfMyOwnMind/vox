import CryptoKit
import Foundation
import Testing
import VoxCore

@testable import VoxSTT

/// Проверки целостности модели идут на синтетическом каталоге: тестам не нужна
/// скачанная модель, и рабочий каталог они не трогают.
@Suite("Целостность модели VoxSTT")
struct STTModelIntegrityTests {

    // MARK: - подготовка

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Собирает каталог модели с manifest по переданным файлам.
    private static func makeModelDirectory(
        files: [String: Data] = [
            "Preprocessor.mlmodelc/coremldata.bin": Data([1, 2, 3, 4]),
            "parakeet_vocab.json": Data("{}".utf8),
        ],
        repo: String = Pins.modelRepo,
        revision: String = Pins.modelRevision
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-stt-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var entries: [ModelManifest.Entry] = []
        for path in files.keys.sorted() {
            let data = files[path]!
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            entries.append(
                .init(path: path, sizeBytes: data.count, sha256: sha256(data)))
        }

        let manifest = ModelManifest(
            modelRepo: repo,
            modelRevision: revision,
            generatedAt: "2026-09-03T00:00:00Z",
            entries: entries
        )
        try JSONEncoder().encode(manifest)
            .write(to: root.appendingPathComponent(ModelManifest.fileName))
        return root
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - проверки

    @Test("Каталог, собранный по manifest, проходит проверку")
    func validDirectoryPasses() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        try ModelIntegrity.verify(directory: directory)
    }

    @Test("Нет каталога — modelMissing")
    func absentDirectoryIsMissing() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-stt-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("проверка прошла без каталога модели")
        } catch let error as VoxError {
            guard case .modelMissing = error else {
                Issue.record("ожидался modelMissing, получено \(error)")
                return
            }
        } catch {
            Issue.record("ожидался VoxError, получено \(error)")
        }
    }

    @Test("Нет manifest — modelMissing")
    func absentManifestIsMissing() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(ModelManifest.fileName))

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("проверка прошла без manifest")
        } catch let error as VoxError {
            guard case .modelMissing = error else {
                Issue.record("ожидался modelMissing, получено \(error)")
                return
            }
        }
    }

    @Test("Файл из manifest пропал — modelMissing")
    func absentFileIsMissing() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent("parakeet_vocab.json"))

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("проверка прошла без файла модели")
        } catch let error as VoxError {
            guard case .modelMissing = error else {
                Issue.record("ожидался modelMissing, получено \(error)")
                return
            }
        }
    }

    @Test("Подделанный байт — modelCorrupted")
    func tamperedByteIsCorrupted() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        let target = directory.appendingPathComponent("Preprocessor.mlmodelc/coremldata.bin")
        var bytes = try Data(contentsOf: target)
        bytes[bytes.startIndex] ^= 0xFF
        try bytes.write(to: target)

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("подделанный байт не обнаружен")
        } catch let error as VoxError {
            guard case .modelCorrupted = error else {
                Issue.record("ожидался modelCorrupted, получено \(error)")
                return
            }
        }
    }

    @Test("Изменённый размер при том же числе файлов — modelCorrupted")
    func changedSizeIsCorrupted() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        let target = directory.appendingPathComponent("parakeet_vocab.json")
        try Data("{\"a\":1}".utf8).write(to: target)

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("изменение размера не обнаружено")
        } catch let error as VoxError {
            guard case .modelCorrupted = error else {
                Issue.record("ожидался modelCorrupted, получено \(error)")
                return
            }
        }
    }

    @Test("Лишний файл вне manifest — modelCorrupted")
    func unexpectedFileIsCorrupted() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        try Data([0]).write(to: directory.appendingPathComponent("EncoderInt4.mlmodelc"))

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("лишний файл не обнаружен")
        } catch let error as VoxError {
            guard case .modelCorrupted = error else {
                Issue.record("ожидался modelCorrupted, получено \(error)")
                return
            }
        }
    }

    @Test("Symlink вместо файла модели — modelCorrupted")
    func symlinkIsCorrupted() throws {
        let directory = try Self.makeModelDirectory()
        defer { Self.remove(directory) }
        let target = directory.appendingPathComponent("parakeet_vocab.json")
        let real = directory.deletingLastPathComponent()
            .appendingPathComponent("vox-stt-tests-link-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: real)
        defer { Self.remove(real) }
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: real)

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("symlink не обнаружен")
        } catch let error as VoxError {
            guard case .modelCorrupted = error else {
                Issue.record("ожидался modelCorrupted, получено \(error)")
                return
            }
        }
    }

    @Test("Чужая ревизия в manifest — modelCorrupted")
    func foreignRevisionIsCorrupted() throws {
        let directory = try Self.makeModelDirectory(revision: String(repeating: "0", count: 40))
        defer { Self.remove(directory) }

        do {
            try ModelIntegrity.verify(directory: directory)
            Issue.record("чужая ревизия не обнаружена")
        } catch let error as VoxError {
            guard case .modelCorrupted = error else {
                Issue.record("ожидался modelCorrupted, получено \(error)")
                return
            }
        }
    }

    @Test("Каталог модели назван так, как его ждёт AsrModels.load(from:)")
    func modelDirectoryNameMatchesLoaderExpectation() {
        // AsrModels.load берёт родителя переданного пути и приписывает Repo.folderName;
        // совпадать должен именно последний компонент, иначе загрузчик уйдёт мимо.
        // Значение проверено эмпирически на FluidAudio v0.15.6: суффикс `-coreml`
        // отбрасывается, поэтому каталог называется без него.
        #expect(ModelLocation.folderName == "parakeet-tdt-0.6b-v3")
        #expect(ModelLocation.bundleSubpath == "Models/parakeet-tdt-0.6b-v3")

        let directory = ModelLocation.modelDirectory()
        #expect(directory.lastPathComponent == ModelLocation.folderName)
        #expect(
            directory.deletingLastPathComponent()
                .appendingPathComponent(ModelLocation.folderName).standardizedFileURL
                == directory.standardizedFileURL)
    }
}
