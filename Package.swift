// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "AIKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .watchOS(.v6),
        .tvOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AIKit",
            targets: ["AIKit"]),
    ],
    dependencies: [
        // SwiftSyntax for macro implementation
        .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.0")
    ],
    targets: [
        // Macro implementation
        .macro(
            name: "AIKitMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        
        // Main library target with macro dependency
        .target(
            name: "AIKit",
            dependencies: ["AIKitMacros"]
        ),
        
        // Test targets
        .testTarget(
            name: "AIKitTests",
            dependencies: ["AIKit"],
            resources: [
                .copy("sample_image.jpg"),
                .copy("sample_image_2.jpg"),
                .copy("sample_audio.m4a"),
                .copy("sample_audio.mp3")
            ]
        ),
        
        .testTarget(
            name: "AIKitMacroTests",
            dependencies: [
                "AIKitMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
    ]
)
