import Foundation
import VoxCore

public enum CleanSelfTest {

    /// Проверки нормализатора и WER. Файлов не трогают: `--self-test` должен
    /// работать и в установленной сборке, где каталога fixtures нет.
    public static func cases() -> [SelfTestCase] {
        [
            SelfTestCase(name: "clean: нормализатор — чистая функция") {
                let input = "  Поднимаем   докер, ээ, докер   и правим nginx  "
                let once = Normalizer().normalize(input)
                let twice = Normalizer().normalize(once)
                guard once == twice else {
                    return "повторное применение меняет результат: «\(once)» → «\(twice)»"
                }
                let expected = "Поднимаем Docker, Docker и правим Nginx"
                guard once == expected else { return "получено «\(once)», ожидалось «\(expected)»" }
                return nil
            },

            SelfTestCase(name: "clean: словарь терминов \(Normalizer.dictionaryVersion)") {
                let got = Normalizer().normalize("собираем на линукс через xcode и кладём в гитхаб")
                let expected = "собираем на Linux через Xcode и кладём в GitHub"
                guard got == expected else { return "получено «\(got)», ожидалось «\(expected)»" }
                return nil
            },

            SelfTestCase(name: "clean: неоднозначное не трогается") {
                let input = "вот значит типа как бы очень очень длинная фраза, нет, короткая"
                let got = Normalizer().normalize(input)
                guard got == input else { return "текст изменён: «\(got)»" }
                return nil
            },

            SelfTestCase(name: "clean: WER на известной паре") {
                let value = WordErrorRate.rate(
                    reference: "this is a test", hypothesis: "this is test")
                guard value == 0.25 else { return "получено \(value), ожидалось 0.25" }
                return nil
            },
        ]
    }
}
