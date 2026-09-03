import AppKit
import Foundation

/// Уровень звука → высоты полос. Чистая функция: тот же вход даёт тот же выход,
/// поэтому её же гоняет служебная проверка.
public enum LevelBars {
    public static let count = 8
    /// Доля высоты капсулы, ниже которой полоса не опускается: в тишине виден ровный ряд.
    public static let minimumHeight: Float = 0.12
    /// RMS тише этого считается тишиной.
    public static let noiseFloor: Float = 0.0015
    /// Экспоненциальное сглаживание. Подъём быстрее спада, но оба далеки от единицы,
    /// поэтому одиночный громкий кадр не даёт скачка на всю высоту.
    public static let riseFactor: Float = 0.35
    public static let fallFactor: Float = 0.12

    /// Полосы к центру выше — ряд читается как один силуэт, а не как забор.
    static let weights: [Float] = [0.45, 0.65, 0.85, 1.0, 1.0, 0.85, 0.65, 0.45]

    /// RMS в нормированный уровень 0...1 по логарифмической шкале.
    public static func level(rms: Float) -> Float {
        let clamped = max(rms.isFinite ? rms : 0, noiseFloor)
        let floorDecibels = 20 * log10(noiseFloor)
        let decibels = 20 * log10(min(clamped, 1))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }

    /// Следующий кадр полос. `previous` неверной длины считается тишиной.
    public static func next(previous: [Float], rms: Float) -> [Float] {
        let target = level(rms: rms)
        let base = previous.count == count ? previous : Array(repeating: minimumHeight, count: count)
        return (0..<count).map { index in
            let wanted = minimumHeight + (1 - minimumHeight) * target * weights[index]
            let current = min(max(base[index], minimumHeight), 1)
            let factor = wanted > current ? riseFactor : fallFactor
            return min(max(current + (wanted - current) * factor, minimumHeight), 1)
        }
    }

    public static var silent: [Float] { Array(repeating: minimumHeight, count: count) }
}

/// Тёмная капсула с полосами. Клики не принимает, фокус не забирает,
/// видна на всех Spaces и поверх fullscreen.
@MainActor
final class IndicatorWindow {
    private let panel: NSPanel
    private let view: IndicatorView
    private var timer: Timer?
    private var latestRMS: Float = 0

    init() {
        let size = NSSize(width: 132, height: 40)
        view = IndicatorView(frame: NSRect(origin: .zero, size: size))
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
    }

    func showRecording() {
        view.mode = .recording
        view.heights = LevelBars.silent
        latestRMS = 0
        place()
        panel.orderFrontRegardless()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Простое состояние обработки: полосы больше не двигаются, второй анимации нет.
    func showProcessing() {
        timer?.invalidate()
        timer = nil
        view.mode = .processing
        view.heights = LevelBars.silent
        view.needsDisplay = true
        place()
        panel.orderFrontRegardless()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    func update(rms: Float) {
        latestRMS = rms
    }

    private func tick() {
        view.heights = LevelBars.next(previous: view.heights, rms: latestRMS)
        view.needsDisplay = true
    }

    private func place() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 16
        ))
    }
}

private final class IndicatorView: NSView {
    enum Mode { case recording, processing }

    var mode: Mode = .recording
    var heights: [Float] = LevelBars.silent

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(calibratedWhite: 0.08, alpha: 0.88).setFill()
        capsule.fill()

        let barWidth: CGFloat = 5
        let gap: CGFloat = 6
        let total = CGFloat(LevelBars.count) * barWidth + CGFloat(LevelBars.count - 1) * gap
        let maxHeight = bounds.height - 16
        var x = bounds.midX - total / 2

        let color = mode == .recording
            ? NSColor(calibratedRed: 0.93, green: 0.20, blue: 0.20, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
        color.setFill()

        for index in 0..<LevelBars.count {
            let value = index < heights.count ? CGFloat(heights[index]) : CGFloat(LevelBars.minimumHeight)
            let height = max(barWidth, maxHeight * value)
            let rect = NSRect(x: x, y: bounds.midY - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}
