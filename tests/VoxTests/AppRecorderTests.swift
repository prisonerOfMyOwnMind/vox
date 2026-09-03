import AVFoundation
import Testing
import VoxCore
@testable import VoxApp

@Suite("Запись: блок tap живёт вне главного потока")
struct AppRecorderTests {

    /// Собирает буфер тишины в формате, который отдаёт настоящий вход.
    private func makeBuffer(frames: AVAudioFrameCount = 512) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
            channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }

    @Test("Блок tap вызывается с аудиопотока и не роняет процесс")
    func tapBlockRunsOffMainThread() async {
        // AVAudioEngine зовёт tap на realtime-потоке. Если блок унаследует
        // изоляцию главного актора, Swift 6 уронит процесс проверкой
        // исполнителя — именно так упала первая живая диктовка.
        let received = SendableBox()
        let block = AudioRecorder.makeTapBlock { buffer in
            received.record(frames: Int(buffer.frameLength))
        }
        let buffer = makeBuffer()

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                #expect(!Thread.isMainThread)
                block(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
                continuation.resume()
            }
        }

        #expect(received.frames == 512)
        #expect(received.calls == 1)
    }

    @Test("Блок tap переживает поток буферов подряд")
    func tapBlockHandlesBurst() async {
        let received = SendableBox()
        let block = AudioRecorder.makeTapBlock { buffer in
            received.record(frames: Int(buffer.frameLength))
        }
        let buffer = makeBuffer(frames: 256)

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<50 {
                    block(buffer, AVAudioTime(sampleTime: 0, atRate: 48_000))
                }
                continuation.resume()
            }
        }

        #expect(received.calls == 50)
        #expect(received.frames == 256 * 50)
    }
}

/// Счётчик, доступный с любого потока.
private final class SendableBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _frames = 0
    private var _calls = 0

    var frames: Int { lock.withLock { _frames } }
    var calls: Int { lock.withLock { _calls } }

    func record(frames count: Int) {
        lock.withLock {
            _frames += count
            _calls += 1
        }
    }
}
