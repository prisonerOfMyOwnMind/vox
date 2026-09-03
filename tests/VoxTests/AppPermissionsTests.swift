import Testing
import Foundation
@testable import VoxApp

@Suite("Разрешения объясняются по отдельности")
struct AppPermissionsTests {

    @Test("Каждое разрешение названо, объяснено и снабжено путём в настройках")
    func everyKindIsExplained() {
        for kind in PermissionKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.purpose.isEmpty)
            #expect(kind.settingsPath.contains("Системные настройки"))
            #expect(kind.settingsPath.contains(kind.title))
        }
        #expect(PermissionKind.allCases.count == 3)
    }

    @Test("Список недостающих содержит только невыданные")
    func missingListsOnlyUngranted() {
        let report = PermissionsReport(
            microphone: .granted, accessibility: .denied, inputMonitoring: .notDetermined)
        #expect(report.missing == [.accessibility, .inputMonitoring])
        #expect(!report.allGranted)
        #expect(report.summary.contains(PermissionKind.accessibility.title))
        #expect(report.summary.contains(PermissionKind.inputMonitoring.title))
    }

    @Test("Выданные разрешения дают короткую строку без инструкции")
    func grantedLineIsShort() {
        let report = PermissionsReport(
            microphone: .granted, accessibility: .granted, inputMonitoring: .granted)
        #expect(report.allGranted)
        #expect(report.missing.isEmpty)
        for kind in PermissionKind.allCases {
            #expect(report.line(for: kind) == "\(kind.title): есть")
        }
        #expect(report.summary == "все разрешения выданы")
    }

    @Test("Невыданное разрешение говорит, чего не хватает и что нажать")
    func missingLineTellsWhatToPress() {
        let report = PermissionsReport(
            microphone: .denied, accessibility: .granted, inputMonitoring: .granted)
        let line = report.line(for: .microphone)
        #expect(line.hasPrefix("Микрофон: нет"))
        #expect(line.contains(PermissionKind.microphone.purpose))
        #expect(line.contains("включить Vox"))
    }

    @Test("Чтение состояния разрешений не бросает и не показывает диалогов")
    func currentIsSideEffectFree() {
        let first = PermissionsCheck.current()
        let second = PermissionsCheck.current()
        #expect(first == second)
    }
}
