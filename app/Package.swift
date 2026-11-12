// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Routines",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Routines", targets: ["Routines"]),
        .library(name: "RoutinesKit", targets: ["RoutinesKit"]),
    ],
    targets: [
        .target(name: "RoutinesKit", resources: [.copy("Resources/prelude.js")]),
        .executableTarget(name: "Routines", dependencies: ["RoutinesKit"], resources: [.copy("Resources/wordmark.png")]),
        .testTarget(name: "RoutinesKitTests", dependencies: ["RoutinesKit"], resources: [.copy("Fixtures")]),
    ]
)
