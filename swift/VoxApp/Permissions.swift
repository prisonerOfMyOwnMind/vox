import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import VoxCore

/// Три разрешения macOS, без которых приложение не работает.
/// Проверяются и объясняются по отдельности: пользователь должен видеть,
/// какого именно доступа не хватает.
public enum PermissionKind: String, Sendable, CaseIterable {
    case microphone
    case accessibility
    case inputMonitoring

    public var title: String {
        switch self {
        case .microphone: return "Микрофон"
        case .accessibility: return "Универсальный доступ"
        case .inputMonitoring: return "Мониторинг ввода"
        }
    }

    /// Зачем нужно именно это разрешение.
    public var purpose: String {
        switch self {
        case .microphone: return "записать речь"
        case .accessibility: return "вставить текст в активное приложение"
        case .inputMonitoring: return "видеть нажатие правой Command"
        }
    }

    /// Что нажать. Путь в Системных настройках, панель «Конфиденциальность и безопасность».
    public var settingsPath: String {
        "Системные настройки → Конфиденциальность и безопасность → \(title) → включить Vox"
    }
}

public enum PermissionState: String, Sendable, Equatable {
    case granted
    case denied
    case notDetermined

    public var word: String {
        switch self {
        case .granted: return "есть"
        case .denied: return "нет"
        case .notDetermined: return "не запрошено"
        }
    }
}

public struct PermissionsReport: Sendable, Equatable {
    public let microphone: PermissionState
    public let accessibility: PermissionState
    public let inputMonitoring: PermissionState

    public init(microphone: PermissionState, accessibility: PermissionState, inputMonitoring: PermissionState) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public func state(of kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone: return microphone
        case .accessibility: return accessibility
        case .inputMonitoring: return inputMonitoring
        }
    }

    public var missing: [PermissionKind] {
        PermissionKind.allCases.filter { state(of: $0) != .granted }
    }

    public var allGranted: Bool { missing.isEmpty }

    /// Строка меню по одному разрешению: состояние, зачем нужно и что нажать.
    public func line(for kind: PermissionKind) -> String {
        let state = state(of: kind)
        if state == .granted {
            return "\(kind.title): есть"
        }
        return "\(kind.title): \(state.word) — нужен, чтобы \(kind.purpose). \(kind.settingsPath)"
    }

    public var summary: String {
        if allGranted { return "все разрешения выданы" }
        return "не хватает: " + missing.map(\.title).joined(separator: ", ")
    }
}

public enum PermissionsCheck {
    /// Читает текущее состояние. Диалогов не показывает и ничего не меняет.
    public static func current() -> PermissionsReport {
        PermissionsReport(
            microphone: microphoneState(),
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            inputMonitoring: CGPreflightListenEventAccess() ? .granted : .denied
        )
    }

    private static func microphoneState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Просит систему показать свой запрос. Ссылки не открываются: диалог рисует macOS.
    /// `completion` вызывается на главном потоке после того, как система ответила.
    @MainActor
    public static func request(_ kind: PermissionKind, completion: @escaping @MainActor () -> Void) {
        switch kind {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in completion() }
            }
        case .accessibility:
            // Значение kAXTrustedCheckOptionPrompt. Константа объявлена как var и не проходит
            // проверку строгой конкуррентности Swift 6.
            let key = "AXTrustedCheckOptionPrompt"
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            completion()
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
            completion()
        }
    }
}
