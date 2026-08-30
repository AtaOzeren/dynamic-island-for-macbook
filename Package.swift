// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchFlow",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "NotchFlow", targets: ["NotchFlow"]),
        .library(name: "NotchFlowCore", targets: ["NotchFlowCore"]),
        .library(name: "NotchFlowProviders", targets: ["NotchFlowProviders"]),
        .library(name: "NotchFlowUI", targets: ["NotchFlowUI"])
    ],
    targets: [
        .target(
            name: "NotchFlowCore",
            dependencies: [],
            path: "Sources/NotchFlowCore",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NotchFlowCoreTests",
            dependencies: ["NotchFlowCore"],
            path: "Tests/NotchFlowCoreTests"
        ),
        .target(
            name: "NotchFlowProviders",
            dependencies: ["NotchFlowCore"],
            path: "Sources/NotchFlowProviders",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NotchFlowProvidersTests",
            dependencies: ["NotchFlowProviders"],
            path: "Tests/NotchFlowProvidersTests"
        ),
        .target(
            name: "NotchFlowUI",
            dependencies: ["NotchFlowCore"],
            path: "Sources/NotchFlowUI",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NotchFlowUITests",
            dependencies: ["NotchFlowUI"],
            path: "Tests/NotchFlowUITests"
        ),
        .executableTarget(
            name: "NotchFlow",
            dependencies: [
                "NotchFlowCore",
                "NotchFlowProviders",
                "NotchFlowUI"
            ],
            path: "NotchFlow",
            exclude: ["Info.plist"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
