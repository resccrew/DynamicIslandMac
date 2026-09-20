// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DynamicIslandMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicIslandMac",
            path: "Sources/DynamicIslandMac"
        )
    ]
)
