import Foundation
import VoxCore
import VoxSTT
import VoxClean
import VoxApp

// Порядок фиксирован контрактом: запрет исходящей сети применяется до всего
// остального, включая app delegate, загрузку модели и любое обращение к FluidAudio.
do {
    let mechanism = try Bootstrap.activateNetworkLockdown()
    FileHandle.standardError.write(Data("запрет исходящей сети: \(mechanism)\n".utf8))
} catch {
    FileHandle.standardError.write(Data("ОСТАНОВ: \(error.localizedDescription)\n".utf8))
    exit(2)
}
let arguments = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print(
        """
        Vox — локальная диктовка для macOS.

          Vox                          запустить приложение в menu bar
          Vox --self-test              служебные проверки без UI
          Vox --transcribe-file <path> распознать файл, напечатать raw и normalized
          Vox --regression <manifest>  прогнать набор fixtures и сохранить результаты
        """)
    exit(2)
}

switch arguments.first {
case nil:
    do {
        try MenuBarApp.run()
    } catch {
        FileHandle.standardError.write(Data("ОСТАНОВ: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "--self-test":
    // Случаи собираются из трёх модулей; каждая ветка наполняет только свой.
    let cases = AppSelfTest.cases() + STTSelfTest.cases() + CleanSelfTest.cases()
    let passed = await SelfTestRunner.run(cases)
    exit(passed ? 0 : 1)

case "--transcribe-file":
    guard arguments.count == 2 else { usage() }
    do {
        let raw = try await STTEntry.transcribeFile(arguments[1])
        let normalized = Normalizer().normalize(raw)
        print("raw:        \(raw)")
        print("normalized: \(normalized)")
    } catch {
        FileHandle.standardError.write(Data("ОСТАНОВ: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "--regression":
    guard arguments.count == 2 else { usage() }
    do {
        let report = try await CleanEntry.runRegression(
            manifestPath: arguments[1],
            transcriber: Transcriber(),
            normalizer: Normalizer()
        )
        print("отчёт: \(report)")
    } catch {
        FileHandle.standardError.write(Data("ОСТАНОВ: \(error.localizedDescription)\n".utf8))
        exit(1)
    }

default:
    usage()
}
