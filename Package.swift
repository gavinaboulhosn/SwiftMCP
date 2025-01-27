// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftMCP",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SwiftMCP",
            targets: ["SwiftMCP"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/gavinaboulhosn/swift-json-schema.git", branch: "main")
    ],
    targets: [
        .target(
            name: "SwiftMCP",
            dependencies: [
                .product(name: "JSONSchema", package: "swift-json-schema")
            ]
        ),
        .testTarget(
            name: "SwiftMCPTests",
            dependencies: [
                "SwiftMCP"
            ]
        ),
    ]
)
