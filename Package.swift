// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FCat",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FCatCore", targets: ["FCatCore"]),
        .executable(name: "FCat", targets: ["FCat"]),
        .executable(name: "FCatCoreTests", targets: ["FCatCoreTests"])
    ],
    targets: [
        .target(
            name: "FCatCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "FCat",
            dependencies: ["FCatCore"]
        ),
        .executableTarget(
            name: "FCatCoreTests",
            dependencies: ["FCatCore"],
            path: "Tests/FCatCoreTests"
        )
    ]
)
