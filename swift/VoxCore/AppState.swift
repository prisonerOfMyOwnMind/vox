import Foundation

/// Состояния приложения. Список закрыт контрактом проекта и не расширяется
/// без решения владельца.
public enum AppState: String, Sendable, Equatable, CaseIterable {
    case starting
    case needsPermissions = "needs permissions"
    case ready
    case recording
    case transcribing
    case error
}
