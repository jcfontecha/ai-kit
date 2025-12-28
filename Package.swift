// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "AIKit",
  platforms: [
    .iOS(.v26),
    .macOS(.v26),
  ],
  products: [
    .library(name: "AIKit", targets: ["AIKit"]),
    .library(name: "AIKitProviders", targets: ["AIKitProviders"]),
    .library(name: "AIKitElements", targets: ["AIKitElements"]),
    .library(name: "AIKitOpenAI", targets: ["AIKitOpenAI"]),
    .library(name: "AIKitOpenRouter", targets: ["AIKitOpenRouter"]),
    .library(name: "AIKitReplicate", targets: ["AIKitReplicate"]),
    .library(name: "AIKitFal", targets: ["AIKitFal"]),
    .executable(name: "aikit-codegen", targets: ["AIKitCodegen"]),
  ],
  dependencies: [
    .package(url: "https://github.com/markiv/SwiftUI-Shimmer.git", from: "1.5.1"),
  ],
  targets: [
    .target(
      name: "AIKitProviders"
    ),
    .target(
      name: "AIKitCore",
      dependencies: ["AIKitProviders"]
    ),
    .target(
      name: "AIKitElements",
      dependencies: [
        "AIKit",
        .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
      ]
    ),
    .target(
      name: "AIKit",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    .target(
      name: "AIKitOpenAI",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    .target(
      name: "AIKitOpenRouter",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    .target(
      name: "AIKitReplicate",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    .target(
      name: "AIKitFal",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    // Internal test utilities (not shipped as a product).
    .target(
      name: "AIKitTestKit",
      dependencies: ["AIKitCore", "AIKitProviders"]
    ),
    .executableTarget(
      name: "AIKitCodegen",
      dependencies: []
    ),
    .testTarget(
      name: "AIKitCoreTests",
      dependencies: ["AIKitCore", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitProvidersTests",
      dependencies: ["AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitOpenRouterTests",
      dependencies: ["AIKitOpenRouter", "AIKitCore", "AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitReplicateTests",
      dependencies: ["AIKitReplicate", "AIKitProviders"]
    ),
    .testTarget(
      name: "AIKitFalTests",
      dependencies: ["AIKitFal", "AIKitProviders"]
    ),
  ]
)
