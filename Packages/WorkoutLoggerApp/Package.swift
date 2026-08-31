// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkoutLoggerApp",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WorkoutLoggerApp", targets: ["WorkoutLoggerApp"]),
    ],
    dependencies: [
        .package(path: "../WorkoutLoggerCore"),
    ],
    targets: [
        .target(
            name: "WorkoutLoggerApp",
            dependencies: [.product(name: "WorkoutLoggerCore", package: "WorkoutLoggerCore")]
        ),
        .testTarget(
            name: "WorkoutLoggerAppTests",
            dependencies: [
                "WorkoutLoggerApp",
                .product(name: "WorkoutLoggerCore", package: "WorkoutLoggerCore"),
            ]
        ),
    ]
)
