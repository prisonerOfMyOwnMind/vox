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

    /// Панель Системных настроек, открывающая нужный список.
    public var settingsURL: URL? {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    /// Можно ли выдать разрешение прямо из приложения.
    ///
    /// Только микрофон: он выдаётся модальным окном. «Универсальный доступ» и
    /// «Мониторинг ввода» macOS выдать из процесса не даёт вообще — их включает
    /// человек переключателем в Системных настройках. Системный API показывает
    /// лишь разовое окно со ссылкой, причём ОДИН раз за жизнь идентичности
    /// приложения; израсходовано — и вызов молча возвращает отказ.
    public var grantableInApp: Bool { self == .microphone }
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

    public init(microphone: PermissionState, accessibility: PermissionState, inputMonitoring: PermissionState)
    {
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

    /// Открывает нужный список в Системных настройках.
    ///
    /// Единственное место, где приложение открывает ссылку, и делает это ТОЛЬКО
    /// по явному нажатию пользователя в меню. Схема локальная, `x-apple.systempreferences`,
    /// сети не касается. Без этого пункт «Выдать» выглядел бы неработающим:
    /// системный API для двух из трёх разрешений ничего не показывает.
    @MainActor
    private static func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Просит систему показать свой запрос и, если разрешение так и не выдано,
    /// открывает нужный список в Системных настройках.
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
            let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            if !trusted { openSettings(for: kind) }
            completion()
        case .inputMonitoring:
            let granted = CGRequestListenEventAccess()
            if !granted { openSettings(for: kind) }
            completion()
        }
    }
}
