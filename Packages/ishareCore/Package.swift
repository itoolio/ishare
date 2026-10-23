// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ishareCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ishareCore", targets: ["ishareCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON", from: "5.0.2"),
    ],
    targets: [
        .target(
            name: "ishareCore",
            dependencies: [.product(name: "SwiftyJSON", package: "SwiftyJSON")]
        ),
        .testTarget(
            name: "ishareCoreTests",
            dependencies: ["ishareCore", .product(name: "SwiftyJSON", package: "SwiftyJSON")],
            linkerSettings: [.linkedFramework("AppIntents")]
        ),
    ]
)
