import Testing
import VoxCore
@testable import VoxApp

@Suite("Запуск: состояние решается по разрешениям И по модели")
struct AppStartupTests {

    @Test("Повреждённая модель отключает диктовку независимо от разрешений")
    func brokenModelBlocksDictation() {
        // Раньше целостность модели проверялась лениво, при первой транскрипции:
        // меню говорило «готов», пользователь наговаривал полминуты и терял
        // запись. Теперь проверка идёт на старте и перекрывает всё остальное.
        for granted in [true, false] {
            let decision = AppController.startupState(
                permissionsGranted: granted,
                permissionsSummary: "не хватает: Микрофон",
                model: .broken("Модель изменена или повреждена: parakeet_vocab.json"))
            #expect(decision.state == .error)
            #expect(decision.message?.contains("повреждена") == true)
        }
    }

    @Test("Пока модель проверяется, приложение не объявляет готовность")
    func checkingIsNotReady() {
        let decision = AppController.startupState(
            permissionsGranted: true, permissionsSummary: "", model: .checking)
        #expect(decision.state == .starting)
    }

    @Test("Нет разрешений — состояние про разрешения, а не про модель")
    func missingPermissionsReported() {
        let decision = AppController.startupState(
            permissionsGranted: false,
            permissionsSummary: "не хватает: Мониторинг ввода",
            model: .ok)
        #expect(decision.state == .needsPermissions)
        #expect(decision.message == "не хватает: Мониторинг ввода")
    }

    @Test("Разрешения выданы и модель цела — готов")
    func allGoodIsReady() {
        let decision = AppController.startupState(
            permissionsGranted: true, permissionsSummary: "", model: .ok)
        #expect(decision.state == .ready)
        #expect(decision.message == nil)
    }
}
