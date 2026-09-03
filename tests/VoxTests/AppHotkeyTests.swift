import Testing
import VoxCore
@testable import VoxApp

@Suite("Хоткей: правая Command")
struct AppHotkeyTests {
    private let right = HotkeyMachine.rightCommandKeyCode
    private let leftCommandKeyCode: Int64 = 55
    /// Правая Command нажата: общий бит Command плюс device-dependent бит правой клавиши.
    private let downFlags = HotkeyMachine.rightCommandFlag | 0x0010_0000
    private let releasedFlags: UInt64 = 0

    @Test("Первое нажатие переключает запись")
    func firstPressStarts() {
        var machine = HotkeyMachine()
        #expect(machine.decide(keyCode: right, flags: downFlags, state: .ready) == .swallowAndStartRecording)
        #expect(machine.isDown)
    }

    @Test("Повторное событие без смены состояния игнорируется")
    func repeatedPressIgnored() {
        var machine = HotkeyMachine()
        _ = machine.decide(keyCode: right, flags: downFlags, state: .ready)
        #expect(machine.decide(keyCode: right, flags: downFlags, state: .recording) == .swallow)
        #expect(machine.decide(keyCode: right, flags: downFlags, state: .recording) == .swallow)
    }

    @Test("Отпускание состояние не меняет, но событие поглощает")
    func releaseChangesNothing() {
        var machine = HotkeyMachine()
        _ = machine.decide(keyCode: right, flags: downFlags, state: .ready)
        #expect(machine.decide(keyCode: right, flags: releasedFlags, state: .recording) == .swallow)
        #expect(!machine.isDown)
        #expect(
            machine.decide(keyCode: right, flags: downFlags, state: .recording) == .swallowAndStopRecording)
    }

    @Test("Левая Command и прочие клавиши проходят без изменений")
    func otherKeysPassThrough() {
        var machine = HotkeyMachine()
        #expect(
            machine.decide(keyCode: leftCommandKeyCode, flags: 0x0010_0008, state: .ready) == .passThrough)
        #expect(machine.decide(keyCode: 58, flags: 0x0008_0000, state: .ready) == .passThrough)
        #expect(machine.decide(keyCode: 0, flags: 0, state: .recording) == .passThrough)
        // Чужие клавиши не должны менять память о правой Command.
        #expect(!machine.isDown)
    }

    @Test("Нажатие во время распознавания игнорируется")
    func pressWhileTranscribingIgnored() {
        var machine = HotkeyMachine()
        #expect(machine.decide(keyCode: right, flags: downFlags, state: .transcribing) == .swallow)
    }

    @Test("Ни одно событие правой Command не доходит до активного приложения")
    func rightCommandNeverPassesThrough() {
        for state in AppState.allCases {
            var machine = HotkeyMachine()
            #expect(machine.decide(keyCode: right, flags: downFlags, state: state) != .passThrough)
            #expect(machine.decide(keyCode: right, flags: releasedFlags, state: state) != .passThrough)
        }
    }

    @Test("Запись начинается только из ready, останавливается только из recording")
    func togglesOnlyInWorkingStates() {
        for state in AppState.allCases {
            var machine = HotkeyMachine()
            let decision = machine.decide(keyCode: right, flags: downFlags, state: state)
            switch state {
            case .ready: #expect(decision == .swallowAndStartRecording)
            case .recording: #expect(decision == .swallowAndStopRecording)
            default: #expect(decision == .swallow)
            }
        }
    }

    @Test("Потерянное отпускание залипает: следующее нажатие не останавливает запись")
    func lostReleaseSticksUntilReset() {
        // Так выглядела живая поломка: обработчик перехвата держали запуском
        // AVAudioEngine, система выключила перехват по таймауту, отпускание до
        // приложения не дошло. Машина считает клавишу удерживаемой.
        var machine = HotkeyMachine()
        let down = HotkeyMachine.rightCommandFlag
        let up: UInt64 = 0

        #expect(
            machine.decide(keyCode: HotkeyMachine.rightCommandKeyCode, flags: down, state: .ready)
                == .swallowAndStartRecording)
        // Отпускание потеряно — событие с flags == up сюда не пришло.
        #expect(machine.isDown)

        // Следующее нажатие выглядит как удержание и поглощается: запись не остановить.
        #expect(
            machine.decide(keyCode: HotkeyMachine.rightCommandKeyCode, flags: down, state: .recording)
                == .swallow)

        // Сброс машины при обратном включении перехвата возвращает управление.
        machine = HotkeyMachine()
        #expect(
            machine.decide(keyCode: HotkeyMachine.rightCommandKeyCode, flags: down, state: .recording)
                == .swallowAndStopRecording)
        // Контроль: нормальный цикл с отпусканием не залипает.
        #expect(
            machine.decide(keyCode: HotkeyMachine.rightCommandKeyCode, flags: up, state: .ready)
                == .swallow)
        #expect(!machine.isDown)
    }
}

@Suite("Состояния: перепроверка разрешений не ломает работу")
struct AppStateGuardTests {

    @Test("Состояния записи и распознавания защищены от перепроверки")
    func busyStatesAreProtected() {
        // Правило: пока идёт запись или распознавание, перепроверка разрешений
        // состояние не трогает. В живом прогоне владельца пункт меню затирал
        // transcribing на ready за 1.1 с до конца распознавания.
        let busy: Set<AppState> = [.recording, .transcribing]
        for state in AppState.allCases {
            #expect(AppController.recheckIsAllowed(in: state) == !busy.contains(state))
        }
    }
}
