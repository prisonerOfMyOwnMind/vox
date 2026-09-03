import FluidAudio
import Foundation
import VoxCore

/// Где лежит модель. Правило одно и без настроек: запущены из `.app` — каталог
/// внутри bundle, иначе `models/...` относительно текущего каталога процесса.
public enum ModelLocation {

    /// Имя каталога модели задаёт FluidAudio, а не мы: `AsrModels.load(from:)`
    /// берёт родителя переданного пути и приписывает `Repo.folderName`.
    /// Для parakeetV3 это `parakeet-tdt-0.6b-v3` — суффикс `-coreml` отбрасывается.
    /// Поэтому имя берётся из зависимости, а не пишется строкой: разойтись нельзя.
    public static let folderName = Repo.parakeetV3.folderName

    /// Каталог модели внутри bundle относительно `Contents/Resources`.
    /// Должен совпадать с `Pins.modelBundleSubpath`: по нему build-app.sh
    /// раскладывает модель в bundle. Равенство стережёт CoreContractsTests.
    public static var bundleSubpath: String { "Models/\(folderName)" }

    public static func modelDirectory() -> URL {
        let bundle = Bundle.main
        if bundle.bundleURL.pathExtension == "app", let resources = bundle.resourceURL {
            return resources.appendingPathComponent(bundleSubpath, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }
}
