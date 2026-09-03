import Testing
import Foundation
@testable import VoxClean

@Suite("WER: доля ошибочных слов")
struct CleanWERTests {

    @Test("Известная пара: одно удаление из четырёх слов даёт ровно 0.25")
    func knownEnglishPair() {
        let value = WordErrorRate.rate(reference: "this is a test", hypothesis: "this is test")
        #expect(value == 0.25)
    }

    @Test("Известная пара на русском: одно удаление и две вставки на пять слов дают 0.6")
    func knownRussianPair() {
        let reference = "поднимаем докер и настраиваем nginx"
        let hypothesis = "поднимаем докер настраиваем nginx на порту"
        #expect(
            WordErrorRate.distance(
                WordErrorRate.words(reference), WordErrorRate.words(hypothesis)) == 3)
        #expect(WordErrorRate.rate(reference: reference, hypothesis: hypothesis) == 0.6)
    }

    @Test("Совпадение даёт ноль, полное расхождение — единицу")
    func boundaries() {
        #expect(WordErrorRate.rate(reference: "собрать проект", hypothesis: "собрать проект") == 0.0)
        #expect(WordErrorRate.rate(reference: "собрать проект", hypothesis: "снести всё") == 1.0)
    }

    @Test("Каждая операция стоит единицу")
    func operationCosts() {
        #expect(WordErrorRate.rate(reference: "а б в г", hypothesis: "а х в г") == 0.25)
        #expect(WordErrorRate.rate(reference: "а б в г", hypothesis: "а б в г д") == 0.25)
        #expect(WordErrorRate.rate(reference: "а б в г", hypothesis: "а в г") == 0.25)
    }

    @Test("Регистр и пунктуация по краям слова на счёт не влияют")
    func tokenisation() {
        #expect(
            WordErrorRate.words("Поднимаем Docker, потом — Nginx!")
                == ["поднимаем", "docker", "потом", "nginx"])
        #expect(
            WordErrorRate.rate(
                reference: "Поднимаем Docker.", hypothesis: "поднимаем docker") == 0.0)
    }

    @Test("Гипотеза длиннее эталона может дать больше единицы")
    func canExceedOne() {
        #expect(WordErrorRate.rate(reference: "да", hypothesis: "нет совсем не так") == 4.0)
    }

    @Test("Пустой эталон: делить не на что, значение задано соглашением")
    func emptyReference() {
        #expect(WordErrorRate.rate(reference: "", hypothesis: "") == 0.0)
        #expect(WordErrorRate.rate(reference: "   ", hypothesis: "что-то") == 1.0)
    }
}
