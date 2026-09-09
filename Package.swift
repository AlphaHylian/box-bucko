// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BoxBucko",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "BoxBucko",
            path: "Sources/BoxBucko",
            resources: [
                .copy("Resources/steve.png")
            ]
        )
    ]
)
