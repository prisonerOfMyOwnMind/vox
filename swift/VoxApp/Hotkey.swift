import CoreGraphics
import Foundation
import VoxCore

/// Что делать с событием клавиатуры.
public enum HotkeyDecision: Sendable, Equatable {
    /// Событие уходит дальше без изменений.
    case passThrough
    /// Событие поглощается, действия нет.
    case swallow
    case swallowAndStartRecording
    case swallowAndStopRecording
}

/// Переходы состояний хоткея. Чистый тип: ни AppKit, ни глобального состояния,
/// поэтому те же переходы гоняются в служебной проверке.
public struct HotkeyMachine: Sendable, Equatable {
    /// Virtual key code правой Command.
    public static let rightCommandKeyCode: Int64 = 54
    /// NX_DEVICERCMDKEYMASK — бит правой Command в device-dependent части flags.
    public static let rightCommandFlag: UInt64 = 0x0000_0010

    /// Правая Command удерживается. Нужна, чтобы отличать первое нажатие от повтора.
    public private(set) var isDown = false

    public init() {}

    public mutating func decide(keyCode: Int64, flags: UInt64, state: AppState) -> HotkeyDecision {
        guard keyCode == Self.rightCommandKeyCode else { return .passThrough }

        let down = flags & Self.rightCommandFlag != 0
        let wasDown = isDown
        isDown = down

        // Отпускание состояние записи не меняет, но и до активного приложения не доходит.
        guard down else { return .swallow }
        // Повторное событие без смены состояния клавиши.
        guard !wasDown else { return .swallow }

        switch state {
        case .ready: return .swallowAndStartRecording
        case .recording: return .swallowAndStopRecording
        case .starting, .needsPermissions, .transcribing, .error: return .swallow
        }
    }
}

/// Живой event tap. Логики переходов не содержит: она в `HotkeyMachine`.
@MainActor
final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var machine = HotkeyMachine()

    private let currentState: @MainActor () -> AppState
    private let onDecision: @MainActor (HotkeyDecision) -> Void

    init(
        currentState: @escaping @MainActor () -> AppState,
        onDecision: @escaping @MainActor (HotkeyDecision) -> Void
    ) {
        self.currentState = currentState
        self.onDecision = onDecision
    }

    /// Ставит tap. Возвращает ошибку, если система его не выдала:
    /// обычно это отсутствие разрешения «Мониторинг ввода».
    func start() throws {
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        // Callback вызывается на том же run loop, куда добавлен source, то есть на главном.
        // Через границу изоляции передаются только скаляры: сам CGEvent остаётся здесь.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags.rawValue
            let decision = MainActor.assumeIsolated {
                monitor.handle(typeRawValue: type.rawValue, keyCode: keyCode, flags: flags)
            }
            return decision == .passThrough ? Unmanaged.passUnretained(event) : nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw VoxError.permissionDenied(
                "\(PermissionKind.inputMonitoring.title). \(PermissionKind.inputMonitoring.settingsPath)")
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Без этого порт остаётся живым на каждом цикле stop()/start().
            CFMachPortInvalidate(tap)
        }
        source = nil
        tap = nil
    }

    /// Читает только тип события, key code и modifier flags. Ничего больше от события не берётся.
    /// В журнал попадают только события ПРАВОЙ Command: чужие клавиши не логируются.
    private func handle(typeRawValue: UInt32, keyCode: Int64, flags: UInt64) -> HotkeyDecision {
        // Система выключает tap по таймауту или по потоку ввода: включаем обратно.
        if typeRawValue == CGEventType.tapDisabledByTimeout.rawValue
            || typeRawValue == CGEventType.tapDisabledByUserInput.rawValue {
            let reason = typeRawValue == CGEventType.tapDisabledByTimeout.rawValue
                ? "таймаут обработчика" : "поток ввода"
            AppLog.problem("перехват клавиатуры отключён системой (\(reason)), включаю обратно")

            // Пока перехват был выключен, события до нас не доходили — в том числе
            // отпускание клавиши. Оставить прежнее isDown значит принять следующее
            // нажатие за удержание и проглотить его: запись не остановится.
            machine = HotkeyMachine()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return .passThrough
        }
        guard typeRawValue == CGEventType.flagsChanged.rawValue else { return .passThrough }

        let wasDown = machine.isDown
        let state = currentState()
        let decision = machine.decide(keyCode: keyCode, flags: flags, state: state)

        if keyCode == HotkeyMachine.rightCommandKeyCode {
            AppLog.note(
                "правая Command: \(machine.isDown ? "нажата" : "отпущена")"
                + ", было \(wasDown ? "нажата" : "отпущена")"
                + ", состояние \(state.rawValue) -> \(decision)")
        }

        if decision != .passThrough {
            // Асинхронно, и это несущее решение. Запуск AVAudioEngine и показ окна
            // занимают десятки миллисекунд; выполненные прямо здесь, они держат
            // обработчик перехвата, система выключает его по таймауту, и события
            // отпускания теряются. Обработчик обязан вернуться немедленно.
            let action = onDecision
            Task { @MainActor in action(decision) }
        }
        return decision
    }
}
