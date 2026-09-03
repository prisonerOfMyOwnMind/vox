import Foundation
import VoxCore

public enum AppSelfTest {
    /// Случаи, которым нужен применённый запрет сети. В `swift test` их нет:
    /// тестовый процесс запускается без seatbelt-профиля.
    public static func lockdownCases() -> [SelfTestCase] {
        [
            SelfTestCase(name: "запрет сети: исходящее соединение отклонено") {
                guard let code = Bootstrap.outboundConnectErrno() else {
                    return "connect(2) на 1.1.1.1:80 прошёл — запрет не действует"
                }
                guard code == EPERM else {
                    return
                        "connect(2) отклонён с errno=\(code) (\(String(cString: strerror(code)))), ожидался EPERM"
                }
                return nil
            },
            SelfTestCase(name: "запрет сети: имя не резолвится") {
                gethostbyname("apple.com") == nil ? nil : "gethostbyname вернул адрес — DNS доступен"
            },
        ]
    }

    /// Случаи без побочных эффектов: те же переходы гоняются и в `swift test`.
    public static func pureCases() -> [SelfTestCase] {
        hotkeyCases() + levelCases() + [
            SelfTestCase(name: "разрешения: каждое названо отдельно") {
                let report = PermissionsCheck.current()
                for kind in PermissionKind.allCases where !report.line(for: kind).hasPrefix(kind.title) {
                    return "строка про \(kind.rawValue) не начинается с названия разрешения"
                }
                let denied = PermissionsReport(
                    microphone: .denied, accessibility: .granted, inputMonitoring: .notDetermined)
                guard denied.missing == [.microphone, .inputMonitoring] else {
                    return "список недостающих неверен: \(denied.missing.map(\.rawValue))"
                }
                guard denied.line(for: .microphone).contains("Системные настройки") else {
                    return "строка не говорит, что нажать"
                }
                return nil
            }
        ]
    }

    public static func cases() -> [SelfTestCase] {
        lockdownCases() + pureCases()
    }

    // MARK: хоткей

    /// Пять обязательных случаев перехода состояний.
    static func hotkeyCases() -> [SelfTestCase] {
        let right = HotkeyMachine.rightCommandKeyCode
        let down = HotkeyMachine.rightCommandFlag | 0x0010_0000
        let up: UInt64 = 0x0000_0000

        return [
            SelfTestCase(name: "хоткей: первое нажатие правой Command начинает запись") {
                var machine = HotkeyMachine()
                let decision = machine.decide(keyCode: right, flags: down, state: .ready)
                return decision == .swallowAndStartRecording ? nil : "получено \(decision)"
            },
            SelfTestCase(name: "хоткей: повторное событие без смены состояния игнорируется") {
                var machine = HotkeyMachine()
                _ = machine.decide(keyCode: right, flags: down, state: .ready)
                let decision = machine.decide(keyCode: right, flags: down, state: .recording)
                return decision == .swallow ? nil : "получено \(decision)"
            },
            SelfTestCase(name: "хоткей: отпускание состояние не меняет") {
                var machine = HotkeyMachine()
                _ = machine.decide(keyCode: right, flags: down, state: .ready)
                let release = machine.decide(keyCode: right, flags: up, state: .recording)
                guard release == .swallow else { return "отпускание дало \(release)" }
                let second = machine.decide(keyCode: right, flags: down, state: .recording)
                return second == .swallowAndStopRecording ? nil : "второе нажатие дало \(second)"
            },
            SelfTestCase(name: "хоткей: левая Command проходит без изменений") {
                var machine = HotkeyMachine()
                let decision = machine.decide(keyCode: 55, flags: 0x0000_0008 | 0x0010_0000, state: .ready)
                return decision == .passThrough ? nil : "получено \(decision)"
            },
            SelfTestCase(name: "хоткей: нажатие во время распознавания игнорируется") {
                var machine = HotkeyMachine()
                let decision = machine.decide(keyCode: right, flags: down, state: .transcribing)
                return decision == .swallow ? nil : "получено \(decision)"
            },
        ]
    }

    // MARK: индикатор

    static func levelCases() -> [SelfTestCase] {
        [
            SelfTestCase(name: "индикатор: ровно восемь полос из любого входа") {
                let odd = LevelBars.next(previous: [0.5, 0.5], rms: 0.3)
                guard odd.count == LevelBars.count else { return "получено \(odd.count) полос" }
                let nan = LevelBars.next(previous: LevelBars.silent, rms: .nan)
                return nan.count == LevelBars.count ? nil : "на NaN получено \(nan.count) полос"
            },
            SelfTestCase(name: "индикатор: тишина держит полосы на минимуме") {
                var bars = Array(repeating: Float(1.0), count: LevelBars.count)
                for _ in 0..<200 { bars = LevelBars.next(previous: bars, rms: 0) }
                let highest = bars.max() ?? 0
                return abs(highest - LevelBars.minimumHeight) < 0.001
                    ? nil : "после тишины максимум \(highest)"
            },
            SelfTestCase(name: "индикатор: один громкий кадр не даёт скачка на всю высоту") {
                let bars = LevelBars.next(previous: LevelBars.silent, rms: 1.0)
                let highest = bars.max() ?? 0
                return highest < 0.5 ? nil : "после одного кадра максимум \(highest)"
            },
            SelfTestCase(name: "индикатор: полосы не выходят за границы") {
                var bars = LevelBars.silent
                for step in 0..<300 { bars = LevelBars.next(previous: bars, rms: step % 2 == 0 ? 4.0 : 0.0) }
                for value in bars where value < LevelBars.minimumHeight || value > 1 {
                    return "полоса вне диапазона: \(value)"
                }
                return nil
            },
            SelfTestCase(name: "индикатор: громче — не ниже") {
                let quiet = LevelBars.level(rms: 0.01)
                let loud = LevelBars.level(rms: 0.2)
                return loud > quiet ? nil : "тихое \(quiet) не меньше громкого \(loud)"
            },
        ]
    }
}
