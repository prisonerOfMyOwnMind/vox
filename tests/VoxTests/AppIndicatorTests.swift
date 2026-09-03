import Testing
import Foundation
@testable import VoxApp

@Suite("Индикатор: уровень звука в высоты полос")
struct AppIndicatorTests {

    @Test("Полос всегда восемь, каким бы ни был вход")
    func alwaysEightBars() {
        #expect(LevelBars.next(previous: [], rms: 0.2).count == 8)
        #expect(LevelBars.next(previous: [0.3, 0.4, 0.5], rms: 0.2).count == 8)
        #expect(LevelBars.next(previous: LevelBars.silent, rms: .nan).count == 8)
        #expect(LevelBars.next(previous: LevelBars.silent, rms: -1).count == 8)
    }

    @Test("Тишина сводит полосы к минимуму")
    func silenceFallsToMinimum() {
        var bars = Array(repeating: Float(1), count: LevelBars.count)
        for _ in 0..<200 { bars = LevelBars.next(previous: bars, rms: 0) }
        for value in bars { #expect(abs(value - LevelBars.minimumHeight) < 0.001) }
    }

    @Test("Сглаживание не даёт скачка от тишины к полной высоте")
    func smoothingPreventsJump() {
        let single = LevelBars.next(previous: LevelBars.silent, rms: 1)
        #expect((single.max() ?? 0) < 0.5)
        var bars = LevelBars.silent
        for _ in 0..<20 { bars = LevelBars.next(previous: bars, rms: 1) }
        #expect((bars.max() ?? 0) > 0.9)
    }

    @Test("Полосы не выходят за границы даже на рваном сигнале")
    func staysInsideBounds() {
        var bars = LevelBars.silent
        for step in 0..<300 {
            bars = LevelBars.next(previous: bars, rms: step % 3 == 0 ? 9 : 0)
            for value in bars {
                #expect(value >= LevelBars.minimumHeight)
                #expect(value <= 1)
            }
        }
    }

    @Test("Уровень монотонен по громкости и ограничен единицей")
    func levelIsMonotonic() {
        #expect(LevelBars.level(rms: 0) == 0)
        #expect(LevelBars.level(rms: LevelBars.noiseFloor) == 0)
        #expect(LevelBars.level(rms: 0.01) < LevelBars.level(rms: 0.1))
        #expect(LevelBars.level(rms: 0.1) < LevelBars.level(rms: 0.9))
        #expect(LevelBars.level(rms: 100) == 1)
    }

    @Test("Функция чистая: тот же вход даёт тот же выход")
    func isPure() {
        let first = LevelBars.next(previous: LevelBars.silent, rms: 0.37)
        let second = LevelBars.next(previous: LevelBars.silent, rms: 0.37)
        #expect(first == second)
    }
}
