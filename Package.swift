// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpsHub",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OpsHub", targets: ["OpsHub"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.15.0")
    ],
    targets: [
        .executableTarget(
            name: "OpsHub",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            resources: [
                .copy("Resources/AppIcon.icns")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(name: "OpsHubTests", dependencies: ["OpsHub"])
    ]
)
