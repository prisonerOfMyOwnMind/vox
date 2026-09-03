import AppKit
import Foundation
import VoxClean
import VoxCore
import VoxSTT

/// Журнал. Пишет только состояния и причины отказов: ни аудио, ни расшифровки,
/// ни буфера обмена, ни нажатых клавиш здесь быть не может.
enum AppLog {
    static func note(_ line: String) {
        FileHandle.standardError.write(Data("vox: \(line)\n".utf8))
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = AudioRecorder()
    private let indicator = IndicatorWindow()
    private let transcriber: any Transcribing = Transcriber()
    private let normalizer: any Normalizing = Normalizer()

    private var hotkey: HotkeyMonitor?
    private var permissions = PermissionsReport(microphone: .denied, accessibility: .denied, inputMonitoring: .denied)
    private var state: AppState = .starting
    private var message: String?

    // MARK: жизненный цикл

    func applicationDidFinishLaunching(_ notification: Notification) {
        recorder.onLevel = { [weak self] rms in self?.indicator.update(rms: rms) }
        hotkey = HotkeyMonitor(
            currentState: { [weak self] in self?.state ?? .starting },
            onDecision: { [weak self] decision in self?.apply(decision) }
        )
        rebuildMenu()
        recheckPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if recorder.isRecording { recorder.stop() }
        indicator.hide()
        hotkey?.stop()
    }

    // MARK: состояние

    private func move(to newState: AppState, message: String? = nil) {
        state = newState
        self.message = message
        AppLog.note("состояние: \(newState.rawValue)" + (message.map { " — \($0)" } ?? ""))
        rebuildMenu()
    }

    /// Возврат в рабочее состояние после ошибки, если повторная попытка безопасна.
    private func fail(_ error: Error, retrySafe: Bool) {
        indicator.hide()
        move(to: .error, message: error.localizedDescription)
        guard retrySafe else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard state == .error else { return }
            recheckPermissions()
        }
    }

    private func recheckPermissions() {
        permissions = PermissionsCheck.current()
        guard permissions.allGranted else {
            hotkey?.stop()
            move(to: .needsPermissions, message: permissions.summary)
            return
        }
        do {
            try hotkey?.start()
            move(to: .ready)
        } catch {
            move(to: .needsPermissions, message: error.localizedDescription)
        }
    }

    // MARK: хоткей

    private func apply(_ decision: HotkeyDecision) {
        switch decision {
        case .swallowAndStartRecording: startRecording()
        case .swallowAndStopRecording: stopAndTranscribe()
        case .swallow, .passThrough: break
        }
    }

    private func startRecording() {
        guard state == .ready else { return }
        do {
            try recorder.start()
            indicator.showRecording()
            move(to: .recording)
        } catch {
            fail(error, retrySafe: true)
        }
    }

    private func stopAndTranscribe() {
        guard state == .recording else { return }
        let samples = recorder.stop()
        indicator.showProcessing()

        guard samples.durationSeconds >= AudioRecorder.minimumSeconds else {
            fail(
                VoxError.recordingTooShort(
                    seconds: samples.durationSeconds, minimum: AudioRecorder.minimumSeconds),
                retrySafe: true)
            return
        }

        move(to: .transcribing)
        Task { @MainActor in
            do {
                let raw = try await transcriber.transcribe(samples)
                let normalized = normalizer.normalize(raw)
                indicator.hide()
                guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    fail(VoxError.transcriptionFailed("речь не распознана"), retrySafe: true)
                    return
                }
                try await Paste.replaceAndPaste(normalized)
                move(to: .ready)
            } catch {
                fail(error, retrySafe: Self.retryIsSafe(after: error))
            }
        }
    }

    /// Повтор безопасен, если причина не в самой сборке. Испорченная или отсутствующая
    /// модель повтором не чинится, приложение остаётся в состоянии ошибки.
    private static func retryIsSafe(after error: Error) -> Bool {
        switch error {
        case VoxError.modelMissing, VoxError.modelCorrupted, VoxError.networkLockdownFailed: return false
        default: return true
        }
    }

    // MARK: меню

    private func rebuildMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName, accessibilityDescription: "Vox")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        // Без этого AppKit сам включает и выключает пункты, и строки-подсказки
        // становятся кликабельными.
        menu.autoenablesItems = false
        menu.addItem(disabled("Vox: \(statusLine)"))
        menu.addItem(.separator())

        let dictation = NSMenuItem(
            title: state == .recording ? "Остановить диктовку" : "Начать диктовку",
            action: #selector(toggleDictation), keyEquivalent: "")
        dictation.target = self
        dictation.isEnabled = state == .ready || state == .recording
        menu.addItem(dictation)

        let recheck = NSMenuItem(
            title: "Проверить разрешения", action: #selector(menuRecheck), keyEquivalent: "")
        recheck.target = self
        menu.addItem(recheck)

        if !permissions.allGranted {
            for kind in permissions.missing {
                menu.addItem(disabled(permissions.line(for: kind)))
                let request = NSMenuItem(
                    title: "Запросить: \(kind.title)", action: #selector(menuRequest(_:)), keyEquivalent: "")
                request.target = self
                request.representedObject = kind.rawValue
                menu.addItem(request)
            }
        }

        menu.addItem(.separator())
        menu.addItem(disabled("Правая ⌘ — начать и остановить диктовку"))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выход", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private var symbolName: String {
        switch state {
        case .starting: return "mic"
        case .needsPermissions, .error: return "exclamationmark.triangle"
        case .ready: return "mic"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        }
    }

    private var statusLine: String {
        var line: String
        switch state {
        case .starting: line = "запуск"
        case .needsPermissions: line = "нет разрешений"
        case .ready: line = "готов"
        case .recording: line = "идёт запись"
        case .transcribing: line = "распознаю"
        case .error: line = "ошибка"
        }
        if let message { line += " — \(message)" }
        return line
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleDictation() {
        switch state {
        case .ready: startRecording()
        case .recording: stopAndTranscribe()
        default: break
        }
    }

    @objc private func menuRecheck() {
        recheckPermissions()
    }

    @objc private func menuRequest(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = PermissionKind(rawValue: raw) else { return }
        PermissionsCheck.request(kind) { [weak self] in self?.recheckPermissions() }
    }

    @objc private func menuQuit() {
        NSApplication.shared.terminate(nil)
    }
}

public enum MenuBarApp {
    /// Запускается только после применённого запрета сети: порядок держит `main.swift`.
    @MainActor
    public static func run() throws {
        let application = NSApplication.shared
        let controller = AppController()
        application.delegate = controller
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(controller) {
            application.run()
        }
    }
}
