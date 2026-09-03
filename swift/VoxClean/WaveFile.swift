import Foundation
import VoxCore

/// Отказы прогона набора fixtures. Отдельный тип: случаи `VoxError` описывают
/// запись и распознавание, а не чтение набора.
public enum RegressionError: Error, LocalizedError, Sendable {
    case manifestUnreadable(path: String, detail: String)
    case manifestEmpty(path: String)
    case audioMissing(path: String)
    case audioUnsupported(path: String, detail: String)
    case reportNotWritten(path: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .manifestUnreadable(let path, let detail):
            return "Manifest не читается: \(path) (\(detail))"
        case .manifestEmpty(let path):
            return "В manifest нет ни одного fixture: \(path)"
        case .audioMissing(let path):
            return "Аудио отсутствует: \(path)"
        case .audioUnsupported(let path, let detail):
            return """
                Аудио не в контрактном формате: \(path) (\(detail)). \
                Требуется WAV mono 16 kHz, Float32 или PCM 16 бит. \
                Привести: afconvert -f WAVE -d LEF32@16000 -c 1 вход.wav выход.wav
                """
        case .reportNotWritten(let path, let detail):
            return "Отчёт не записан: \(path) (\(detail))"
        }
    }
}

/// Минимальное чтение WAV в контрактный `AudioSamples`.
/// Пересчёта частоты и сведения каналов нет намеренно: и то и другое молча
/// меняет материал, по которому считается WER.
enum WaveFile {

    static func read(at url: URL) throws -> AudioSamples {
        let path = url.path
        guard let data = try? Data(contentsOf: url) else {
            throw RegressionError.audioMissing(path: path)
        }
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
            ascii(bytes, 0, 4) == "RIFF",
            ascii(bytes, 8, 4) == "WAVE"
        else {
            throw RegressionError.audioUnsupported(path: path, detail: "не RIFF/WAVE")
        }

        var format: (code: Int, channels: Int, sampleRate: Int, bits: Int)?
        var payload: ArraySlice<UInt8>?

        // Чанки идут подряд и выровнены по чётной границе; неизвестные
        // пропускаются. `say` вставляет перед data чанк выравнивания FLLR.
        var offset = 12
        while offset + 8 <= bytes.count {
            let id = ascii(bytes, offset, 4)
            let size = Int(uint32(bytes, offset + 4))
            let body = offset + 8
            guard size >= 0, body + size <= bytes.count else { break }
            if id == "fmt ", size >= 16 {
                format = (
                    code: Int(uint16(bytes, body)),
                    channels: Int(uint16(bytes, body + 2)),
                    sampleRate: Int(uint32(bytes, body + 4)),
                    bits: Int(uint16(bytes, body + 14))
                )
            } else if id == "data" {
                payload = bytes[body..<(body + size)]
            }
            offset = body + size + (size % 2)
        }

        guard let format else {
            throw RegressionError.audioUnsupported(path: path, detail: "нет чанка fmt")
        }
        guard let payload else {
            throw RegressionError.audioUnsupported(path: path, detail: "нет чанка data")
        }
        guard format.channels == AudioSamples.channelCount else {
            throw RegressionError.audioUnsupported(
                path: path, detail: "каналов \(format.channels), нужен 1")
        }
        guard format.sampleRate == Int(AudioSamples.sampleRate) else {
            throw RegressionError.audioUnsupported(
                path: path, detail: "частота \(format.sampleRate) Hz, нужна 16000 Hz")
        }

        switch (format.code, format.bits) {
        case (3, 32):
            var values: [Float] = []
            values.reserveCapacity(payload.count / 4)
            var index = payload.startIndex
            while index + 4 <= payload.endIndex {
                values.append(Float(bitPattern: uint32(bytes, index)))
                index += 4
            }
            return AudioSamples(values: values)
        case (1, 16):
            var values: [Float] = []
            values.reserveCapacity(payload.count / 2)
            var index = payload.startIndex
            while index + 2 <= payload.endIndex {
                let sample = Int16(bitPattern: uint16(bytes, index))
                values.append(Float(sample) / 32768.0)
                index += 2
            }
            return AudioSamples(values: values)
        default:
            throw RegressionError.audioUnsupported(
                path: path,
                detail: "формат \(format.code), \(format.bits) бит")
        }
    }

    // MARK: - Чтение little-endian полей

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> String {
        String(decoding: bytes[offset..<(offset + count)], as: UTF8.self)
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
