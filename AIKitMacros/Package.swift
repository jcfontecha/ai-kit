// swift-tools-version: 5.10
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "AIKitMacros",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "AIKitMacro", targets: ["AIKitMacro"]),
  ],
  dependencies: [
    // Depends on the main AIKit package (this repo root).
    .package(name: "AIKit", path: ".."),
    // Macro implementation.
    .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0"),
  ],
  targets: [
    .macro(
      name: "AIKitMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "AIKitMacro",
      dependencies: [
        .product(name: "AIKit", package: "AIKit"),
        "AIKitMacros",
      ]
    ),
    .testTarget(
      name: "AIKitMacroTests",
      dependencies: [
        "AIKitMacro",
        "AIKitMacros",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
  ]
)
