// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "AIKitE2E",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [],
  dependencies: [
    .package(name: "AIKit", path: "../.."),
    .package(name: "AIKitMacros", path: "../../AIKitMacros"),
  ],
  targets: [
    .testTarget(
      name: "AIKitE2ETests",
      dependencies: [
        .product(name: "AIKit", package: "AIKit"),
        .product(name: "AIKitOpenRouter", package: "AIKit"),
        .product(name: "AIKitOpenAI", package: "AIKit"),
        .product(name: "AIKitMacro", package: "AIKitMacros"),
      ]
    ),
  ]
)
