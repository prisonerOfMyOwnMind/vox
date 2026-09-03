import Foundation

/// Единственный источник правды по закреплённым внешним ревизиям.
/// Значения дублируются в Package.swift и в scripts/; расхождение ловит self-test.
public enum Pins {
    /// Тег и commit зависимости FluidAudio.
    public static let fluidAudioTag = "v0.15.6"
    public static let fluidAudioCommit = "4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b"

    /// Репозиторий модели на HuggingFace и его точная ревизия.
    public static let modelRepo = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
    public static let modelRevision = "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"

    /// Каталог модели внутри bundle относительно Contents/Resources.
    /// Имя последнего компонента задано FluidAudio: AsrModels.repoPath берёт родителя
    /// переданного пути и приписывает Repo.folderName, а folderName отбрасывает суффикс
    /// `-coreml`. Поэтому здесь `parakeet-tdt-0.6b-v3`, а не имя репозитория модели.
    /// Значение читает scripts/build-app.sh; runtime берёт его из ModelLocation.
    /// Совпадение двух источников стережёт тест CoreContractsTests.
    public static let modelBundleSubpath = "Models/parakeet-tdt-0.6b-v3"

    /// Версия приложения. Пишется в результаты regression.
    public static let appVersion = "0.1.0"
}
