import Foundation

/// Manifest встроенной модели. Пишется контролируемой сборкой, проверяется до загрузки.
/// Runtime использует его только для проверки: скачивание и починка запрещены.
public struct ModelManifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// Путь относительно каталога модели.
        public let path: String
        public let sizeBytes: Int
        /// SHA-256 в нижнем регистре.
        public let sha256: String

        public init(path: String, sizeBytes: Int, sha256: String) {
            self.path = path
            self.sizeBytes = sizeBytes
            self.sha256 = sha256
        }
    }

    public let modelRepo: String
    public let modelRevision: String
    public let generatedAt: String
    public let entries: [Entry]

    public init(modelRepo: String, modelRevision: String, generatedAt: String, entries: [Entry]) {
        self.modelRepo = modelRepo
        self.modelRevision = modelRevision
        self.generatedAt = generatedAt
        self.entries = entries
    }

    /// Имя файла manifest внутри каталога модели.
    public static let fileName = "vox-model-manifest.json"
}
