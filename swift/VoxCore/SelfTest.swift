import Foundation

/// Общий формат результатов служебных проверок.
/// Каждый модуль отдаёт свои случаи; исполняемый файл только собирает и печатает.
public struct SelfTestCase: Sendable {
    public let name: String
    /// Возвращает nil при успехе, иначе причину падения.
    public let run: @Sendable () async -> String?

    public init(name: String, run: @escaping @Sendable () async -> String?) {
        self.name = name
        self.run = run
    }
}

public struct SelfTestOutcome: Sendable, Equatable {
    public let name: String
    public let passed: Bool
    public let detail: String?
    public let seconds: Double

    public init(name: String, passed: Bool, detail: String?, seconds: Double) {
        self.name = name
        self.passed = passed
        self.detail = detail
        self.seconds = seconds
    }
}

public enum SelfTestRunner {
    /// Прогоняет случаи по порядку и печатает построчный отчёт.
    /// Возвращает true, если упавших нет.
    public static func run(_ cases: [SelfTestCase]) async -> Bool {
        var outcomes: [SelfTestOutcome] = []
        for testCase in cases {
            let started = Date()
            let failure = await testCase.run()
            let outcome = SelfTestOutcome(
                name: testCase.name,
                passed: failure == nil,
                detail: failure,
                seconds: Date().timeIntervalSince(started)
            )
            outcomes.append(outcome)
            let mark = outcome.passed ? "PASS" : "FAIL"
            var line = String(format: "%@  %@  (%.3f s)", mark, outcome.name, outcome.seconds)
            if let detail = outcome.detail {
                line += "\n      \(detail)"
            }
            print(line)
        }
        let failed = outcomes.filter { !$0.passed }
        print("")
        print("итого: \(outcomes.count - failed.count)/\(outcomes.count) пройдено")
        return failed.isEmpty
    }
}
