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
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SwwmCoreTests", dependencies: ["SwwmCore"]),
    ]
)
