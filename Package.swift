// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KerNotch",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "KerNotch", targets: ["KerNotch"]),
        .library(name: "KerNotchCore", targets: ["KerNotchCore"]),
        .library(name: "KerNotchProviders", targets: ["KerNotchProviders"]),
        .library(name: "KerNotchUI", targets: ["KerNotchUI"]),
    ],
    targets: [
        .target(
            name: "KerNotchCore",
            dependencies: [],
            path: "Sources/KerNotchCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KerNotchCoreTests",
            dependencies: ["KerNotchCore"],
            path: "Tests/KerNotchCoreTests"
        ),
        .target(
            name: "KerNotchProviders",
            dependencies: ["KerNotchCore"],
            path: "Sources/KerNotchProviders"
        ),
        .testTarget(
            name: "KerNotchProvidersTests",
            dependencies: ["KerNotchProviders"],
            path: "Tests/KerNotchProvidersTests"
        ),
        .target(
            name: "KerNotchUI",
            dependencies: ["KerNotchCore"],
            path: "Sources/KerNotchUI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "KerNotchUITests",
            dependencies: ["KerNotchUI"],
            path: "Tests/KerNotchUITests"
        ),
        .executableTarget(
            name: "KerNotch",
            dependencies: [
                "KerNotchCore",
                "KerNotchProviders",
                "KerNotchUI",
            ],
            path: "KerNotch",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "Localizable.xcstrings",
            ]
        ),
        .testTarget(
            name: "KerNotchTests",
            dependencies: ["KerNotch"],
            path: "Tests/KerNotchTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
