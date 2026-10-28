// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "pbip-reader",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PBIPKit", targets: ["PBIPKit"]),
        .executable(name: "pbip", targets: ["pbip"]),
        .executable(name: "pbip-reader-app", targets: ["PBIPReaderApp"]),
    ],
    dependencies: [
        // Seule dépendance externe autorisée (voir docs/NOTES.md).
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PBIPKit"),
        .executableTarget(
            name: "pbip",
            dependencies: [
                "PBIPKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Application SwiftUI (phase 4) : seule cible qui dépend de l'interface.
        .executableTarget(
            name: "PBIPReaderApp",
            dependencies: ["PBIPKit"]
        ),
        .testTarget(
            name: "PBIPKitTests",
            dependencies: ["PBIPKit"],
            // Les fichiers d'exemple (Tests/Fixtures) sont localisés via #filePath.
            exclude: []
        ),
    ]
)
