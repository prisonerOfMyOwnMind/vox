import Foundation
import VoxCore

/// Итог применения запрета исходящей сети.
public enum LockdownStatus: Sendable, Equatable {
    /// Запрет применён указанным механизмом.
    case applied(String)
}

public enum Bootstrap {
    /// Профиль seatbelt. `(allow default)` оставляет процессу всё остальное:
    /// mach-порты WindowServer, TCC, CoreAudio и чтение bundle не относятся
    /// к `network-outbound` и под запрет не попадают.
    /// Запрет накрывает и unix-сокеты, поэтому обращение к mDNSResponder тоже
    /// закрыто и имена не резолвятся.
    static let profile = """
    (version 1)
    (allow default)
    (deny network-outbound)
    """

    static let mechanism = "seatbelt sandbox_init: deny network-outbound"

    private typealias SandboxInit = @convention(c) (
        UnsafePointer<CChar>?, UInt64, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
    ) -> Int32
    private typealias SandboxFreeError = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    /// RTLD_DEFAULT на Darwin.
    private static func anyLoadedImage() -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: -2)
    }

    /// Вызывается первой строкой процесса, до app delegate, до любого обращения
    /// к FluidAudio и до загрузки модели.
    /// `sandbox_init` объявлен устаревшим и не экспортируется в модуль Darwin,
    /// поэтому символ берётся через `dlsym`.
    public static func activateNetworkLockdown() throws -> LockdownStatus {
        guard let symbol = dlsym(anyLoadedImage(), "sandbox_init") else {
            throw VoxError.networkLockdownFailed("в процессе нет символа sandbox_init")
        }
        let sandboxInit = unsafeBitCast(symbol, to: SandboxInit.self)

        var errorBuffer: UnsafeMutablePointer<CChar>?
        let code = profile.withCString { sandboxInit($0, 0, &errorBuffer) }
        let message = errorBuffer.map { String(cString: $0) }
        if let errorBuffer, let free = dlsym(anyLoadedImage(), "sandbox_free_error") {
            unsafeBitCast(free, to: SandboxFreeError.self)(errorBuffer)
        }
        guard code == 0 else {
            throw VoxError.networkLockdownFailed(message ?? "sandbox_init вернул \(code)")
        }
        return .applied(mechanism)
    }

    /// Пробное исходящее соединение. Возвращает `errno`, если соединение отклонено,
    /// и `nil`, если открыть его удалось. Используется служебной проверкой:
    /// пакеты никуда не уходят, адрес не резолвится и данные не отправляются.
    static func outboundConnectErrno(host: String = "1.1.1.1", port: UInt16 = 80) -> Int32? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return errno }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr(host)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0 ? nil : errno
    }
}
