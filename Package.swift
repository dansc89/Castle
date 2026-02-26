// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Castle",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Castle"
        ),
        .testTarget(
            name: "CastleTests",
            dependencies: ["Castle"]
        )
    ]
)
