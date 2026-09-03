// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vox", targets: ["Vox"])
    ],
    dependencies: [
        // Закреплено точной ревизией. Moving branch запрещён контрактом проекта.
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            revision: "4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b"
        )
    ],
    targets: [
        .target(name: "VoxCore", path: "swift/VoxCore"),
        .target(
            name: "VoxSTT",
            dependencies: ["VoxCore", .product(name: "FluidAudio", package: "FluidAudio")],
            path: "swift/VoxSTT"
        ),
        .target(name: "VoxClean", dependencies: ["VoxCore"], path: "swift/VoxClean"),
        .target(name: "VoxApp", dependencies: ["VoxCore", "VoxSTT", "VoxClean"], path: "swift/VoxApp"),
        .executableTarget(
            name: "Vox",
            dependencies: ["VoxCore", "VoxSTT", "VoxClean", "VoxApp"],
            path: "swift/Vox"
        ),
        .testTarget(
            name: "VoxTests",
            dependencies: ["VoxCore", "VoxSTT", "VoxClean", "VoxApp"],
            path: "tests/VoxTests"
        ),
    ]
)
