import Testing
import Foundation
@testable import VoxApp

@Suite("Служебные проверки VoxApp")
struct AppSelfTestCasesTests {

    @Test("Случаи без побочных эффектов проходят")
    func pureCasesPass() async {
        for testCase in AppSelfTest.pureCases() {
            let failure = await testCase.run()
            #expect(failure == nil, "\(testCase.name): \(failure ?? "")")
        }
    }

    @Test("Пять обязательных случаев хоткея на месте")
    func hotkeyCasesArePresent() {
        #expect(AppSelfTest.hotkeyCases().count == 5)
    }

    @Test("Имена случаев уникальны и ничего не пропало")
    func namesAreUniqueAndComplete() {
        let names = AppSelfTest.cases().map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count == AppSelfTest.lockdownCases().count + AppSelfTest.pureCases().count)
        #expect(!AppSelfTest.lockdownCases().isEmpty)
    }

    @Test("Профиль seatbelt запрещает исходящие соединения")
    func profileDeniesOutbound() {
        #expect(Bootstrap.profile.contains("(deny network-outbound)"))
        #expect(Bootstrap.profile.hasPrefix("(version 1)"))
        // Разрешающих исключений в профиле быть не должно.
        #expect(!Bootstrap.profile.contains("(allow network"))
    }
}
