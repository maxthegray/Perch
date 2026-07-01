// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Perch",
            dependencies: [
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
        )
    ]
)
