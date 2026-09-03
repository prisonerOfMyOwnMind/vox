import AVFoundation
import Foundation
import Testing
import VoxCore

@testable import VoxSTT

@Suite("Чтение аудио в VoxSTT")
struct STTAudioFileReaderTests {

    /// Пишет во временный файл секунду синуса в заданном формате и возвращает путь.
    private static func writeWave(sampleRate: Double, channels: AVAudioChannelCount) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-stt-tests-\(UUID().uuidString).wav")
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels,
            interleaved: false)!
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
            interleaved: false)

        let frames = AVAudioFrameCount(sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = buffer.floatChannelData![channel]
            for frame in 0..<Int(frames) {
                data[frame] = sin(2 * .pi * 440 * Float(frame) / Float(sampleRate)) * 0.5
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test("Stereo 44.1 kHz приводится к mono 16 kHz Float32")
    func stereoIsConvertedToContractForm() throws {
        let url = try Self.writeWave(sampleRate: 44_100, channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try AudioFileReader.read(path: url.path)
        // Секунда звука на выходе — 16000 отсчётов; хвост ресемплера даёт единицы кадров.
        #expect(abs(samples.values.count - 16_000) <= 64)
        #expect(abs(samples.durationSeconds - 1.0) < 0.01)
        #expect(samples.values.contains { $0 != 0 })
    }

    @Test("Mono 16 kHz читается без преобразования и без потери длины")
    func monoContractFormatIsReadAsIs() throws {
        let url = try Self.writeWave(sampleRate: 16_000, channels: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let samples = try AudioFileReader.read(path: url.path)
        #expect(samples.values.count == 16_000)
    }

    @Test("Нет файла — понятная ошибка, а не падение")
    func missingFileThrows() {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("vox-stt-tests-\(UUID().uuidString).wav").path
        #expect(throws: VoxError.self) { try AudioFileReader.read(path: path) }
    }
}
