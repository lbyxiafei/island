// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic, no UI framework. Keep it free of AppKit so it stays testable.
        .target(name: "IslandCore"),
        .executableTarget(name: "Island", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
