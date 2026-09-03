import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import VoxCore

/// Полный снимок буфера обмена: все items, все их типы и данные.
public struct ClipboardSnapshot: Sendable, Equatable {
    /// По одному словарю на item: сырое имя типа → данные.
    public let items: [[String: Data]]

    public init(items: [[String: Data]]) {
        self.items = items
    }

    public static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item -> [String: Data] in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type.rawValue] = data }
            }
            return stored
        }
        return ClipboardSnapshot(items: items.filter { !$0.isEmpty })
    }

    public func restore(into pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { stored -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in stored { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

@MainActor
public enum Paste {
    /// Virtual key code клавиши V.
    static let keyV: CGKeyCode = 9
    /// Пауза перед проверкой буфера: активное приложение должно успеть прочитать вставку.
    static let verifyDelay: Duration = .milliseconds(150)

    /// Кладёт текст, шлёт Cmd+V и возвращает прежнее содержимое, если пользователь
    /// его сам не менял. Содержимое расшифровки никуда не пишется, кроме буфера.
    public static func replaceAndPaste(
        _ text: String,
        pasteboard: NSPasteboard = .general
    ) async throws {
        guard AXIsProcessTrusted() else {
            throw VoxError.pasteFailed(
                "нет разрешения «\(PermissionKind.accessibility.title)». \(PermissionKind.accessibility.settingsPath)")
        }

        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(into: pasteboard)
            throw VoxError.pasteFailed("буфер обмена не принял текст")
        }
        let stamp = pasteboard.changeCount

        do {
            try sendCommandV()
        } catch {
            // Соседняя ветка отказа снимок восстанавливает, эта — нет: буфер
            // пользователя остался бы затёртым расшифровкой.
            snapshot.restore(into: pasteboard)
            throw error
        }

        try? await Task.sleep(for: verifyDelay)

        // Пользователь мог скопировать своё, пока шла вставка: тогда его содержимое
        // трогать нельзя.
        guard pasteboard.changeCount == stamp, pasteboard.string(forType: .string) == text else { return }
        snapshot.restore(into: pasteboard)
    }

    private static func sendCommandV() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw VoxError.pasteFailed("система не выдала источник событий")
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            throw VoxError.pasteFailed("система не выдала событие клавиатуры")
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
