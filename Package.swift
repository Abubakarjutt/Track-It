// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkoutLoggerCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "WorkoutLoggerCore", targets: ["WorkoutLoggerCore"]),
    ],
    targets: [
        .target(name: "WorkoutLoggerCore"),
        .testTarget(
            name: "WorkoutLoggerCoreTests",
            dependencies: ["WorkoutLoggerCore"]
        ),
    ]
)
