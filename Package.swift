// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpsHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpsHub", targets: ["OpsHub"])
    ],
    targets: [
        .executableTarget(name: "OpsHub"),
        .testTarget(name: "OpsHubTests", dependencies: ["OpsHub"])
    ]
)
