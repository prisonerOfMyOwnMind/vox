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
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let ratio: Double
    private let onLevel: @Sendable (Float) -> Void

    init(converter: AVAudioConverter, target: AVAudioFormat, ratio: Double, onLevel: @escaping @Sendable (Float) -> Void) {
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
    func closeAndTake() -> [Float] {
        lock.lock()
        accepting = false
        let taken = values
        values.removeAll(keepingCapacity: false)
        lock.unlock()
        return taken
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
        guard error == nil, output.frameLength > 0, let channel = output.floatChannelData?[0] else { return }

        let frames = Int(output.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<frames { sumOfSquares += channel[index] * channel[index] }
        let rms = (sumOfSquares / Float(frames)).squareRoot()

        lock.lock()
        if accepting { values.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames)) }
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
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AudioSamples.sampleRate,
            channels: AVAudioChannelCount(AudioSamples.channelCount),
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: target) else {
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

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            sink.append(buffer)
        }

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
    }

    /// Останавливает запись и отдаёт накопленное ровно один раз. Копилка очищается здесь,
    /// поэтому любой исход распознавания оставляет её пустой.
    @discardableResult
    func stop() -> AudioSamples {
        guard isRecording, let engine, let sink else { return AudioSamples(values: []) }
        let values = sink.closeAndTake()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.sink = nil
        isRecording = false
        return AudioSamples(values: values)
    }
}
