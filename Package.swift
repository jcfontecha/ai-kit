// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "AIKit",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "AIKit", targets: ["AIKit"]),
    .library(name: "AIKitCore", targets: ["AIKitCore"]),
    .library(name: "AIKitProviders", targets: ["AIKitProviders"]),
    .library(name: "AIKitOpenAI", targets: ["AIKitOpenAI"]),
    .library(name: "AIKitOpenRouter", targets: ["AIKitOpenRouter"]),
    .library(name: "AIKitReplicate", targets: ["AIKitReplicate"]),
    .library(name: "AIKitFal", targets: ["AIKitFal"]),
    .executable(name: "aikit-codegen", targets: ["AIKitCodegen"]),
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
