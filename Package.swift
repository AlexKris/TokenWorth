// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenWorth",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TokenWorthCore", targets: ["TokenWorthCore"]),
        .executable(name: "TokenWorth", targets: ["TokenWorthApp"]),
        .executable(name: "tokenworth-cli", targets: ["TokenWorthCLI"])
    ],
    targets: [
        .target(
            name: "TokenWorthCore",
            path: "Sources/TokenWorthCore"
        ),
        .executableTarget(
            name: "TokenWorthApp",
            dependencies: ["TokenWorthCore"],
            path: "Sources/TokenWorthApp"
        ),
        .executableTarget(
            name: "TokenWorthCLI",
            dependencies: ["TokenWorthCore"],
            path: "Sources/TokenWorthCLI"
        ),
        .testTarget(
            name: "TokenWorthCoreTests",
            dependencies: ["TokenWorthCore"],
            path: "Tests/TokenWorthCoreTests"
        )
    ]
)
