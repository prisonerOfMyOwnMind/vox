import AVFoundation
import Foundation
import VoxCore

/// Одноразовая подача буфера в AVAudioConverter. Блок подачи объявлен `@Sendable`,
/// а `AVAudioPCMBuffer` таковым не является; коробка живёт только внутри одного
/// вызова `convert` и читается тем же потоком, который этот вызов сделал.
private final class InputFeed: @unchecked Sendable {
    private var pending: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { pending = buffer }

    func take() -> AVAudioPCMBuffer? {
        defer { pending = nil }
        return pending
    }
}

/// Копилка samples. Отдельный класс, потому что tap AVAudioEngine вызывается
/// на аудиопотоке, а не на главном.
private final class SampleSink: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Float] = []
    private var accepting = false
    private var accepted = 0
    private var dropped = 0
    /// Первая причина отказа преобразования. Дальше не переписывается:
    /// важна причина, с которой всё началось, а не последняя из сотни.
    private var firstFailure: String?
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let ratio: Double
    private let onLevel: @Sendable (Float) -> Void

    init(
        converter: AVAudioConverter, target: AVAudioFormat, ratio: Double,
        onLevel: @escaping @Sendable (Float) -> Void
    ) {
        self.converter = converter
        self.target = target
        self.ratio = ratio
        self.onLevel = onLevel
    }

    func open() {
        lock.lock()
        values.removeAll(keepingCapacity: true)
        accepting = true
        lock.unlock()
    }

    /// Запрещает добавление samples и отдаёт накопленное, очищая копилку.
    func closeAndTake() -> (values: [Float], accepted: Int, dropped: Int, failure: String?) {
        lock.lock()
        accepting = false
        let taken = values
        let counts = (accepted, dropped, firstFailure)
        values.removeAll(keepingCapacity: false)
        lock.unlock()
        return (taken, counts.0, counts.1, counts.2)
    }

    func discard() {
        lock.lock()
        accepting = false
        values.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let open = accepting
        lock.unlock()
        guard open else { return }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        let feed = InputFeed(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            guard let pending = feed.take() else {
                status.pointee = .noDataNow
                return nil
            }
            status.pointee = .haveData
            return pending
        }
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else {
            // Раньше здесь стоял молчаливый return: звук пропадал, индикатор
            // продолжал показывать запись, а на выходе пользователь получал
            // сообщение про слишком короткую запись, к делу не относящееся.
            // Журналировать прямо тут нельзя — это realtime-поток; поэтому
            // считаем и отдаём наверх при остановке.
            lock.lock()
            dropped += 1
            if firstFailure == nil {
                firstFailure =
                    error.map { "преобразование звука отказало: \($0.localizedDescription)" }
                    ?? "преобразование звука не дало кадров"
            }
            lock.unlock()
            return
        }

        let frames = Int(output.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<frames { sumOfSquares += channel[index] * channel[index] }
        let rms = (sumOfSquares / Float(frames)).squareRoot()

        lock.lock()
        if accepting {
            values.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            accepted += 1
        }
        lock.unlock()

        onLevel(rms)
    }
}

/// Микрофон → mono 16 kHz Float32 в памяти. Файлов на диск нет.
@MainActor
final class AudioRecorder {
    /// Короче этого запись отклоняется: обычно это случайное касание клавиши.
    static let minimumSeconds: Double = 0.5

    private var engine: AVAudioEngine?
    private var sink: SampleSink?
    private(set) var isRecording = false

    /// Уровень приходит на главный поток примерно с частотой аудиобуферов.
    var onLevel: (@MainActor (Float) -> Void)?

    /// Блок, который AVAudioEngine вызывает НА АУДИОПОТОКЕ, а не на главном.
    ///
    /// Обязан быть `nonisolated`, а принимаемое замыкание — `@Sendable`.
    /// `AVAudioNodeTapBlock` в SDK не помечен `@Sendable`, поэтому замыкание,
    /// созданное прямо внутри `@MainActor`-метода, унаследовало бы изоляцию
    /// главного актора. Swift 6 вставляет в такое замыкание динамическую
    /// проверку исполнителя, и на первом же буфере с realtime-потока процесс
    /// падает с EXC_BREAKPOINT. Ровно это и случилось на первой живой диктовке
    /// (crash 2026-09-03, поток RealtimeMessenger.mServiceQueue).
    ///
    /// Тот же приём уже применён к `SampleSink.onLevel` — там `@Sendable`
    /// стоял с самого начала, поэтому этот путь не падал.
    nonisolated static func makeTapBlock(
        _ receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in receive(buffer) }
    }

    func start() throws {
        guard !isRecording else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw VoxError.permissionDenied(
                "\(PermissionKind.microphone.title). \(PermissionKind.microphone.settingsPath)")
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoxError.transcriptionFailed("вход микрофона не отдал формат: устройство недоступно")
        }
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioSamples.sampleRate,
                channels: AVAudioChannelCount(AudioSamples.channelCount),
                interleaved: false
            ), let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            throw VoxError.transcriptionFailed(
                "нет преобразования \(inputFormat.sampleRate) Гц в \(AudioSamples.sampleRate) Гц")
        }

        let handler = onLevel
        let sink = SampleSink(
            converter: converter,
            target: target,
            ratio: target.sampleRate / inputFormat.sampleRate,
            onLevel: { rms in
                guard let handler else { return }
                Task { @MainActor in handler(rms) }
            }
        )
        sink.open()

        input.installTap(
            onBus: 0, bufferSize: 2048, format: inputFormat,
            block: Self.makeTapBlock { [sink] buffer in sink.append(buffer) })

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            sink.discard()
            throw VoxError.transcriptionFailed("не удалось запустить запись: \(error.localizedDescription)")
        }

        self.engine = engine
        self.sink = sink
        isRecording = true
        AppLog.note(
            "запись начата: вход \(Int(inputFormat.sampleRate)) Гц / "
                + "\(inputFormat.channelCount) кан. -> \(Int(target.sampleRate)) Гц / моно")
    }

    /// Останавливает запись и отдаёт накопленное ровно один раз. Копилка очищается здесь,
    /// поэтому любой исход распознавания оставляет её пустой.
    /// Итог записи: сам звук и то, что случилось по дороге.
    /// Счётчики нужны, чтобы отказ звукового тракта не выглядел как короткая запись.
    struct Outcome {
        let samples: AudioSamples
        let acceptedBuffers: Int
        let droppedBuffers: Int
        /// Первая причина отказа преобразования, если он был.
        let failure: String?
    }

    @discardableResult
    func stop() -> Outcome {
        guard isRecording, let engine, let sink else {
            return Outcome(
                samples: AudioSamples(values: []), acceptedBuffers: 0, droppedBuffers: 0, failure: nil)
        }
        let taken = sink.closeAndTake()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.sink = nil
        isRecording = false
        return Outcome(
            samples: AudioSamples(values: taken.values),
            acceptedBuffers: taken.accepted,
            droppedBuffers: taken.dropped,
            failure: taken.failure)
    }
}
