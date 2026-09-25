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
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "NorseMixologyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "NorseMixologyCoreTests",
            dependencies: ["NorseMixologyCore"],
            resources: [.copy("Resources/taxonomy.json"), .copy("Resources/recipes.json")]
        )
    ]
)
