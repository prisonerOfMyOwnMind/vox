import Testing
import AppKit
import Foundation
@testable import VoxApp

/// Работаем на именованном буфере: общий буфер пользователя тесты не трогают.
@Suite("Буфер обмена: снимок и восстановление")
@MainActor
struct AppClipboardTests {

    private func scratchPasteboard(_ name: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("vox.tests.\(name)"))
        pasteboard.clearContents()
        return pasteboard
    }

    @Test("Снимок сохраняет все типы одного item")
    func snapshotKeepsEveryType() {
        let pasteboard = scratchPasteboard("types")
        let item = NSPasteboardItem()
        item.setString("исходный текст", forType: .string)
        item.setData(Data([0x01, 0x02, 0x03]), forType: NSPasteboard.PasteboardType("com.vox.test.binary"))
        pasteboard.writeObjects([item])

        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items[0][NSPasteboard.PasteboardType.string.rawValue] != nil)
        #expect(snapshot.items[0]["com.vox.test.binary"] == Data([0x01, 0x02, 0x03]))
    }

    @Test("Восстановление возвращает прежнее содержимое после подмены")
    func restoreBringsContentBack() {
        let pasteboard = scratchPasteboard("restore")
        let item = NSPasteboardItem()
        item.setString("было", forType: .string)
        item.setData(Data([0xAA]), forType: NSPasteboard.PasteboardType("com.vox.test.binary"))
        pasteboard.writeObjects([item])

        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        #expect(pasteboard.setString("стало", forType: .string))
        #expect(pasteboard.string(forType: .string) == "стало")

        snapshot.restore(into: pasteboard)
        #expect(pasteboard.string(forType: .string) == "было")
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("com.vox.test.binary")) == Data([0xAA]))
    }

    @Test("Снимок нескольких items переживает round-trip")
    func multipleItemsSurvive() {
        let pasteboard = scratchPasteboard("multi")
        let first = NSPasteboardItem()
        first.setString("один", forType: .string)
        let second = NSPasteboardItem()
        second.setString("два", forType: NSPasteboard.PasteboardType("com.vox.test.other"))
        pasteboard.writeObjects([first, second])

        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.count == 2)
        pasteboard.clearContents()
        snapshot.restore(into: pasteboard)
        #expect(ClipboardSnapshot.capture(from: pasteboard) == snapshot)
    }

    @Test("Пустой буфер восстанавливается пустым")
    func emptySnapshotClears() {
        let pasteboard = scratchPasteboard("empty")
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        #expect(snapshot.items.isEmpty)
        #expect(pasteboard.setString("мусор", forType: .string))
        snapshot.restore(into: pasteboard)
        #expect(pasteboard.string(forType: .string) == nil)
    }
}
