// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NorseMixologyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NorseMixologyCore",
            targets: ["NorseMixologyCore"]
        )
    ],
    targets: [
        .target(
            name: "NorseMixologyCore"
        ),
        .testTarget(
            name: "NorseMixologyCoreTests",
            dependencies: ["NorseMixologyCore"]
        )
    ]
)
