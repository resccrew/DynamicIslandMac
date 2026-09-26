// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DynamicIslandMac",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure display geometry, kept AppKit-free so it can be unit-tested.
        .target(
            name: "IslandGeometry",
            path: "Sources/IslandGeometry"
        ),
        .executableTarget(
            name: "DynamicIslandMac",
            dependencies: ["IslandGeometry"],
            path: "Sources/DynamicIslandMac"
        ),
        .testTarget(
            name: "IslandGeometryTests",
            dependencies: ["IslandGeometry"],
            path: "Tests/IslandGeometryTests"
        )
    ]
)
