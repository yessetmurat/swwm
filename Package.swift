// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swwm",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.6.0"),
    ],
    targets: [
        .target(name: "SwwmCore", dependencies: ["TOMLKit"]),
        .executableTarget(
            name: "swwm",
            dependencies: ["SwwmCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // A bare binary (no .app) still carries its bundle id and name for
            // TCC and codesign: Info.plist goes into __TEXT,__info_plist.
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                "-Xlinker", "Resources/Info.plist",
            ])]
        ),
        .testTarget(name: "SwwmCoreTests", dependencies: ["SwwmCore"]),
    ]
)
