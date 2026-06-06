// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Perch",
            path: "Sources/Perch",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
