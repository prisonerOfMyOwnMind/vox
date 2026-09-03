@preconcurrency import AVFoundation
import Foundation
import VoxCore

/// Чтение аудиофайла в контрактную форму: mono, 16 kHz, Float32, в памяти.
/// Временных файлов не создаёт.
enum AudioFileReader {

    /// Размер порции, которой файл подаётся в конвертер.
    private static let chunkFrames: AVAudioFrameCount = 1 << 15

    static func read(path: String) throws -> AudioSamples {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoxError.transcriptionFailed("нет файла \(path)")
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw VoxError.transcriptionFailed(
                "файл \(path) не читается как аудио: \(error.localizedDescription)")
        }

        let sourceFormat = file.processingFormat
        let sourceFrames = file.length
        guard sourceFrames > 0 else {
            throw VoxError.transcriptionFailed("в файле \(path) нет звука")
        }

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AudioSamples.sampleRate,
                channels: AVAudioChannelCount(AudioSamples.channelCount),
                interleaved: false
            )
        else {
            throw VoxError.transcriptionFailed("не строится формат mono 16 kHz Float32")
        }
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw VoxError.transcriptionFailed(
                "не строится преобразование из \(sourceFormat) в mono 16 kHz Float32")
        }
        guard let chunk = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: chunkFrames)
        else {
            throw VoxError.transcriptionFailed("не выделяется буфер чтения")
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        // Запас на хвост ресемплера: конвертер отдаёт не больше запрошенной ёмкости.
        let capacity = AVAudioFrameCount((Double(sourceFrames) * ratio).rounded(.up)) + 4096
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else {
            throw VoxError.transcriptionFailed("не выделяется буфер под \(capacity) кадров")
        }

        // AVAudioFile.read(into:) отдаёт файл порциями по пакетам, поэтому конвертер
        // тянет столько порций, сколько нужно, а не одну: иначе теряется хвост файла.
        nonisolated(unsafe) var readFailure: Error?
        nonisolated(unsafe) var remaining = sourceFrames
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            let wanted = AVAudioFrameCount(min(Int64(chunkFrames), remaining))
            guard wanted > 0 else {
                outStatus.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: chunk, frameCount: wanted)
            } catch {
                readFailure = error
                outStatus.pointee = .endOfStream
                return nil
            }
            guard chunk.frameLength > 0 else {
                outStatus.pointee = .endOfStream
                return nil
            }
            remaining -= Int64(chunk.frameLength)
            outStatus.pointee = .haveData
            return chunk
        }

        if let readFailure {
            throw VoxError.transcriptionFailed(
                "файл \(path) не дочитывается: \(readFailure.localizedDescription)")
        }
        if let conversionError {
            throw VoxError.transcriptionFailed(
                "преобразование аудио не удалось: \(conversionError.localizedDescription)")
        }
        guard status == .haveData || status == .endOfStream || status == .inputRanDry else {
            throw VoxError.transcriptionFailed("преобразование аудио вернуло статус \(status.rawValue)")
        }

        return AudioSamples(values: values(of: targetBuffer))
    }

    private static func values(of buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
