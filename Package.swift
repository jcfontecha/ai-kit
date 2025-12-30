// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

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
    .library(name: "AIKitMacro", targets: ["AIKitMacro"]),
    .executable(name: "aikit-codegen", targets: ["AIKitCodegen"]),
  ],
  dependencies: [
    .package(url: "https://github.com/markiv/SwiftUI-Shimmer.git", from: "1.5.1"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0"),
  ],
  targets: [
    .target(
      name: "AIKitProviders"
    ),
    .target(
      name: "AIKitElements",
      dependencies: [
        "AIKit",
        .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
      ]
    ),
    .target(
      name: "AIKit",
      dependencies: ["AIKitProviders"]
    ),
    .target(
      name: "AIKitOpenAI",
      dependencies: ["AIKitProviders"]
    ),
    .target(
      name: "AIKitOpenRouter",
      dependencies: ["AIKitProviders"]
    ),
    .target(
      name: "AIKitReplicate",
      dependencies: ["AIKitProviders"]
    ),
    .target(
      name: "AIKitFal",
      dependencies: ["AIKitProviders"]
    ),
    // Internal test utilities (not shipped as a product).
    .target(
      name: "AIKitTestKit",
      dependencies: ["AIKitProviders"]
    ),
    .executableTarget(
      name: "AIKitCodegen",
      dependencies: []
    ),
    .macro(
      name: "AIKitMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      path: "AIKitMacros/Sources/AIKitMacros"
    ),
    .target(
      name: "AIKitMacro",
      dependencies: [
        "AIKit",
        "AIKitMacros",
      ],
      path: "AIKitMacros/Sources/AIKitMacro"
    ),
    .testTarget(
      name: "AIKitTests",
      dependencies: ["AIKit", "AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitProvidersTests",
      dependencies: ["AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitOpenRouterTests",
      dependencies: ["AIKitOpenRouter", "AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitElementsTests",
      dependencies: ["AIKitElements", "AIKit", "AIKitProviders", "AIKitTestKit"]
    ),
    .testTarget(
      name: "AIKitReplicateTests",
      dependencies: ["AIKitReplicate", "AIKitProviders"]
    ),
    .testTarget(
      name: "AIKitFalTests",
      dependencies: ["AIKitFal", "AIKitProviders"]
    ),
    .testTarget(
      name: "AIKitMacroTests",
      dependencies: [
        "AIKitMacro",
        "AIKitMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ],
      path: "AIKitMacros/Tests/AIKitMacroTests"
    ),
  ]
)
