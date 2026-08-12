// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "SmartPerchCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/SmartPerchCore"
        ),
        .target(
            name: "SmartPerchVision",
            dependencies: ["SmartPerchCore"],
            path: "Sources/SmartPerchVision"
        ),
        .executableTarget(
            name: "Perch",
            dependencies: [
                "SmartPerchCore",
                "SmartPerchVision",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Perch",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // The embedded Sparkle.framework lives in Perch.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "SmartPerchCoreTests",
            dependencies: [
                "SmartPerchCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/SmartPerchCoreTests"
        ),
        .testTarget(
            name: "SmartPerchVisionTests",
            dependencies: ["SmartPerchVision"],
            path: "Tests/SmartPerchVisionTests"
        ),
        .testTarget(
            name: "PerchTests",
            dependencies: ["Perch"],
            path: "Tests/PerchTests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
