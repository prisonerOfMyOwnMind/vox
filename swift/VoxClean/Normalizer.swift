import Foundation
import VoxCore

/// Детерминированная консервативная обработка расшифровки.
///
/// Функция чистая: одинаковый вход даёт одинаковый выход, состояния нет,
/// ко времени, локали и сети обращений нет.
///
/// Разрешённый набор преобразований закрыт и состоит ровно из пяти пунктов:
///  1. обрезка пробелов по краям;
///  2. схлопывание повторных пробелов внутри строки;
///  3. удаление однозначных слов-паразитов (только звуки колебания);
///  4. схлопывание подряд идущего дубля одного слова;
///  5. приведение технических терминов к каноническому написанию по словарю.
///
/// Всё остальное запрещено: намерение не разбирается, предложения не
/// переписываются, факты не добавляются, пунктуация по смыслу не меняется.
/// Нет уверенности в конкретном преобразовании — соответствующий фрагмент
/// возвращается как есть.
public struct Normalizer: Normalizing {

    /// Версия таблиц правил: словарь терминов, список паразитов и список слов,
    /// которым повтор разрешён. Результаты regression сравнимы между прогонами
    /// только при одинаковой версии, поэтому она попадает в имя файла отчёта.
    /// Меняется при любой правке любой из трёх таблиц.
    public static let dictionaryVersion = "clean-dict-1"

    public init() {}

    public func normalize(_ raw: String) -> String {
        // Построчно: перевод строки — не пробел, схлопывать его нельзя.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let processed = lines.map { Self.normalizeLine(String($0)) }
        return processed.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Одна строка

    private static func normalizeLine(_ line: String) -> String {
        // split по пробельным символам сам схлопывает повторные пробелы при сборке.
        var tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        tokens = tokens.filter { !isDroppableFiller($0) }
        tokens = tokens.map(canonicalTerm(in:))
        tokens = collapseAdjacentDuplicates(tokens)
        return tokens.joined(separator: " ")
    }

    // MARK: - Разбор токена на пунктуацию и ядро

    /// Делит токен на ведущую пунктуацию, буквенно-цифровое ядро и хвостовую пунктуацию.
    private static func parts(_ token: String) -> (lead: String, core: String, trail: String) {
        let chars = Array(token)
        var start = 0
        while start < chars.count, !chars[start].isLetter, !chars[start].isNumber { start += 1 }
        if start == chars.count { return (token, "", "") }
        var end = chars.count - 1
        while end > start, !chars[end].isLetter, !chars[end].isNumber { end -= 1 }
        return (
            String(chars[0..<start]),
            String(chars[start...end]),
            String(chars[(end + 1)...])
        )
    }

    // MARK: - 3. Слова-паразиты

    /// Список сознательно КОРОТКИЙ и состоит только из звуков колебания:
    /// «э», «ээ», «эээ», «эм», «мм», «ммм» и их варианты через дефис.
    ///
    /// Осмысленные слова сюда не входят и не удаляются никогда: «вот», «значит»,
    /// «типа», «как бы», «короче», «в общем». В русском они регулярно несут
    /// смысл, отличить паразита от значимого употребления без разбора намерения
    /// нельзя, а разбор намерения запрещён.
    ///
    /// Одиночное «м» тоже не трогается: оно бывает сокращением (метр, мужской).
    /// Английские «uh», «um» не трогаются: fixtures на английскую речь нет.
    static func isFillerCore(_ core: String) -> Bool {
        let squashed = core.replacingOccurrences(of: "-", with: "").lowercased()
        guard !squashed.isEmpty else { return false }
        // «э», «ээ», «эээ», «э-э-э»
        if squashed.allSatisfy({ $0 == "э" }) { return true }
        // «мм», «ммм»; одиночное «м» исключено длиной
        if squashed.count >= 2, squashed.allSatisfy({ $0 == "м" }) { return true }
        // «эм», «эмм»
        if squashed.count >= 2, squashed.first == "э",
           squashed.dropFirst().allSatisfy({ $0 == "м" }) { return true }
        return false
    }

    /// Токен удаляется целиком вместе со своей запятой.
    /// Если паразит несёт точку, восклицательный или вопросительный знак —
    /// удаление потеряло бы конец предложения, а восстанавливать пунктуацию
    /// запрещено. Такой токен остаётся нетронутым.
    /// По той же причине не удаляется паразит, несущий заглавную букву начала
    /// фразы: следующее слово осталось бы строчным, а поднимать регистр — это
    /// шестое преобразование в закрытом наборе (owner-решение 2026-09-03).
    private static func isDroppableFiller(_ token: String) -> Bool {
        let (lead, core, trail) = parts(token)
        guard isFillerCore(core), lead.isEmpty else { return false }
        guard !startsUppercase(core) else { return false }
        return trail.isEmpty || trail == ","
    }

    /// Ядро токена начинается с прописной буквы.
    private static func startsUppercase(_ core: String) -> Bool {
        guard let first = core.first else { return false }
        return first.isUppercase
    }

    // MARK: - 4. Подряд идущий дубль слова

    /// Слова, для которых повтор в русском — усиление, а не сбой распознавания.
    /// Короче пяти символов не схлопывается вовсе, поэтому «да да», «ну ну»,
    /// «так так», «чуть чуть», «еле еле» в список не нужны.
    static let repeatableWords: Set<String> = [
        "очень", "давай", "давайте", "долго", "давно", "быстро", "много", "хорошо",
    ]

    private static let minimumCollapsibleLength = 5

    private static func collapseAdjacentDuplicates(_ tokens: [String]) -> [String] {
        var result: [String] = []
        result.reserveCapacity(tokens.count)
        for token in tokens {
            if let previous = result.last, isCollapsibleDuplicate(previous: previous, token) {
                // Остаётся ВТОРОЙ токен: вся пунктуация пары висит на нём,
                // и выбросить надо голое слово, а не конец предложения.
                // Но если первый нёс заглавную, а второй нет, схлопывание
                // уронило бы регистр — тогда пара остаётся как есть.
                if startsUppercase(parts(previous).1), !startsUppercase(parts(token).1) {
                    result.append(token)
                    continue
                }
                result[result.count - 1] = token
            } else {
                result.append(token)
            }
        }
        return result
    }

    static func isCollapsibleDuplicate(previous: String, _ token: String) -> Bool {
        let first = parts(previous)
        let second = parts(token)
        // Первый токен должен быть голым словом. Запятая или точка после него —
        // это перечисление или граница предложения («Docker, Docker, Kubernetes»),
        // а не сбой распознавания.
        guard first.lead.isEmpty, first.trail.isEmpty, second.lead.isEmpty else { return false }
        guard first.core.lowercased() == second.core.lowercased() else { return false }
        guard first.core.count >= minimumCollapsibleLength else { return false }
        guard first.core.allSatisfy({ $0.isLetter }) else { return false }
        guard !repeatableWords.contains(first.core.lowercased()) else { return false }
        return true
    }

    // MARK: - 5. Словарь технических терминов

    /// Небольшой словарь: ключ — токен в нижнем регистре, значение — каноническое
    /// написание. Кириллические варианты добавлены только там, где обратное
    /// прочтение однозначно. Неоднозначные транслитерации («редис» — овощ,
    /// «питон» — змея, «свифт» — не только язык) в словарь не входят.
    ///
    /// Каждое каноническое написание само является ключом после lowercased(),
    /// поэтому подстановка идемпотентна.
    static let terms: [String: String] = [
        "docker": "Docker", "докер": "Docker",
        "nginx": "Nginx", "энджинкс": "Nginx", "нжинкс": "Nginx",
        "grpc": "gRPC",
        "postgresql": "PostgreSQL",
        "postgres": "Postgres", "постгрес": "Postgres",
        "kubernetes": "Kubernetes", "кубернетес": "Kubernetes",
        "github": "GitHub", "гитхаб": "GitHub",
        "linux": "Linux", "линукс": "Linux",
        "macos": "macOS",
        "xcode": "Xcode",
        "json": "JSON",
        "yaml": "YAML",
        "sql": "SQL",
        "api": "API",
    ]

    private static func canonicalTerm(in token: String) -> String {
        let (lead, core, trail) = parts(token)
        guard !core.isEmpty, let canonical = terms[core.lowercased()] else { return token }
        return lead + canonical + trail
    }
}
