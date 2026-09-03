import Foundation
import VoxCore

/// Итог применения запрета исходящей сети.
public enum LockdownStatus: Sendable, Equatable {
    /// Запрет применён указанным механизмом.
    case applied(String)
    /// Заглушка bootstrap. Ветка `deliver` обязана убрать этот случай.
    case notImplemented
}

public enum Bootstrap {
    /// Вызывается первой строкой процесса, до app delegate, до любого обращения
    /// к FluidAudio и до загрузки модели.
    /// Ветка `deliver`: применить запрет и бросить `VoxError.networkLockdownFailed`,
    /// если применить не удалось.
    public static func activateNetworkLockdown() throws -> LockdownStatus {
        .notImplemented
    }
}

public enum MenuBarApp {
    /// ЗАГЛУШКА bootstrap. Реализация — ветка `deliver`.
    public static func run() throws {
        throw VoxError.notImplemented("VoxApp.MenuBarApp.run")
    }
}

public enum AppSelfTest {
    /// Ветка `deliver` добавляет сюда: hotkey state machine и обработку уровня звука.
    public static func cases() -> [SelfTestCase] { [] }
}
