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
      targets: ["SwiftMCP"])
  ],
  dependencies: [
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.3.2"),
    .package(url: "https://github.com/airbnb/swift", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "SwiftMCP",
      dependencies: [
        .product(name: "JSONSchema", package: "swift-json-schema")
      ]),
    .testTarget(
      name: "SwiftMCPTests",
      dependencies: ["SwiftMCP"]),
  ])
