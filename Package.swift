// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PMSet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PMSet",
            path: "Sources/PMSet"
        )
    ]
)
