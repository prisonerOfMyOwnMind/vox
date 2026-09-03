import CryptoKit
import Foundation
import VoxCore

/// Проверка встроенной модели до загрузки. Приложение модель не чинит и не
/// докачивает: любое расхождение — остановка с `modelMissing` или `modelCorrupted`.
public enum ModelIntegrity {

    /// Читает manifest и сверяет каталог с ним целиком: состав, размеры, SHA-256.
    /// Лишние файлы, symlink и спецфайлы отвергаются.
    public static func verify(directory: URL) throws {
        let manifest = try readManifest(directory: directory)

        guard manifest.modelRepo == Pins.modelRepo else {
            throw VoxError.modelCorrupted(
                "manifest описывает репозиторий \(manifest.modelRepo), ожидался \(Pins.modelRepo)")
        }
        guard manifest.modelRevision == Pins.modelRevision else {
            throw VoxError.modelCorrupted(
                "manifest описывает ревизию \(manifest.modelRevision), ожидалась \(Pins.modelRevision)")
        }
        guard !manifest.entries.isEmpty else {
            throw VoxError.modelCorrupted("manifest не перечисляет ни одного файла")
        }

        let actual = try regularFiles(in: directory)

        let expected = Set(manifest.entries.map(\.path))
        let unexpected = Set(actual.keys).subtracting(expected).sorted()
        if let first = unexpected.first {
            throw VoxError.modelCorrupted(
                "в каталоге модели файл вне manifest: \(first) (всего лишних \(unexpected.count))")
        }

        for entry in manifest.entries {
            guard let url = actual[entry.path] else {
                throw VoxError.modelMissing("файл модели отсутствует: \(entry.path)")
            }
            let size = try fileSize(of: url, path: entry.path)
            guard size == entry.sizeBytes else {
                throw VoxError.modelCorrupted(
                    "размер \(entry.path): \(size) байт при ожидаемых \(entry.sizeBytes)")
            }
            let digest = try sha256(of: url, path: entry.path)
            guard digest == entry.sha256 else {
                throw VoxError.modelCorrupted(
                    "SHA-256 \(entry.path): \(digest) при ожидаемом \(entry.sha256)")
            }
        }
    }

    public static func readManifest(directory: URL) throws -> ModelManifest {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw VoxError.modelMissing("нет каталога модели \(directory.path)")
        }

        let manifestURL = directory.appendingPathComponent(ModelManifest.fileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw VoxError.modelMissing("нет \(ModelManifest.fileName) в \(directory.path)")
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            throw VoxError.modelCorrupted(
                "\(ModelManifest.fileName) не читается: \(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(ModelManifest.self, from: data)
        } catch {
            throw VoxError.modelCorrupted(
                "\(ModelManifest.fileName) не разбирается: \(error.localizedDescription)")
        }
    }

    /// Все обычные файлы каталога, кроме самого manifest, по пути относительно каталога.
    private static func regularFiles(in directory: URL) throws -> [String: URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.producesRelativePathURLs]
            )
        else {
            throw VoxError.modelMissing("каталог модели не обходится: \(directory.path)")
        }

        var files: [String: URL] = [:]
        for case let url as URL in enumerator {
            let relativePath = url.relativePath
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: Set(keys))
            } catch {
                throw VoxError.modelCorrupted(
                    "не читается запись каталога \(relativePath): \(error.localizedDescription)")
            }
            if values.isSymbolicLink == true {
                throw VoxError.modelCorrupted("symlink в каталоге модели: \(relativePath)")
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw VoxError.modelCorrupted("не обычный файл в каталоге модели: \(relativePath)")
            }
            if relativePath == ModelManifest.fileName {
                continue
            }
            files[relativePath] = url
        }
        return files
    }

    private static func fileSize(of url: URL, path: String) throws -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize else {
                throw VoxError.modelCorrupted("размер файла недоступен: \(path)")
            }
            return size
        } catch let error as VoxError {
            throw error
        } catch {
            throw VoxError.modelCorrupted("размер \(path) не читается: \(error.localizedDescription)")
        }
    }

    private static func sha256(of url: URL, path: String) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw VoxError.modelCorrupted("\(path) не открывается: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            throw VoxError.modelCorrupted("\(path) не дочитывается: \(error.localizedDescription)")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
