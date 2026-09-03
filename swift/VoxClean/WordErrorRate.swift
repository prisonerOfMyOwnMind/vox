import Foundation

/// Доля ошибочных слов: расстояние редактирования по последовательностям слов,
/// делённое на длину эталона. Стандартная библиотека, без зависимостей.
public enum WordErrorRate {

    /// Слова для сравнения: нижний регистр, разбиение по пробельным символам,
    /// пунктуация по краям слова отброшена. Внутренние дефисы сохраняются,
    /// потому что «из-за» и «из за» — разные варианты произнесённого.
    public static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { token -> String in
                var chars = Array(token)
                while let first = chars.first, !first.isLetter, !first.isNumber {
                    chars.removeFirst()
                }
                while let last = chars.last, !last.isLetter, !last.isNumber {
                    chars.removeLast()
                }
                return String(chars)
            }
            .filter { !$0.isEmpty }
    }

    /// Расстояние Левенштейна по словам: вставка, удаление и замена стоят по единице.
    public static func distance(_ reference: [String], _ hypothesis: [String]) -> Int {
        if reference.isEmpty { return hypothesis.count }
        if hypothesis.isEmpty { return reference.count }

        var previous = Array(0...hypothesis.count)
        var current = [Int](repeating: 0, count: hypothesis.count + 1)

        for i in 1...reference.count {
            current[0] = i
            for j in 1...hypothesis.count {
                let substitution = previous[j - 1] + (reference[i - 1] == hypothesis[j - 1] ? 0 : 1)
                let deletion = previous[j] + 1
                let insertion = current[j - 1] + 1
                current[j] = min(substitution, deletion, insertion)
            }
            swap(&previous, &current)
        }
        return previous[hypothesis.count]
    }

    /// Ошибки делятся на длину ЭТАЛОНА, поэтому значение может превысить 1.0,
    /// если гипотеза длиннее эталона.
    ///
    /// Пустой эталон: деления нет. Пустая гипотеза — 0.0, иначе 1.0.
    /// Значение возвращается, а не считается ошибкой, чтобы прогон набора
    /// не падал из-за одной строки.
    public static func rate(reference: String, hypothesis: String) -> Double {
        let referenceWords = words(reference)
        let hypothesisWords = words(hypothesis)
        guard !referenceWords.isEmpty else {
            return hypothesisWords.isEmpty ? 0.0 : 1.0
        }
        return Double(distance(referenceWords, hypothesisWords)) / Double(referenceWords.count)
    }
}
