# Installation

This guide covers how to install AIKit in your Swift project.

## Requirements

- **Swift**: 5.9 or later
- **Platforms**: iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+
- **Xcode**: 15.0 or later

## Swift Package Manager

### Using Package.swift

Add AIKit as a dependency in your `Package.swift` file:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YourProject",
    dependencies: [
        .package(url: "https://github.com/jcfontecha/ai-kit.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "YourTarget",
            dependencies: ["AIKit"]
        )
    ]
)
```

### Using Xcode

1. Open your project in Xcode
2. Go to **File** → **Add Package Dependencies...**
3. Enter the repository URL: `https://github.com/jcfontecha/ai-kit.git`
4. Select the version you want to use (recommend "Up to Next Major Version")
5. Click **Add Package**
6. Select your target and click **Add Package**

## Importing AIKit

Once installed, import AIKit in your Swift files:

```swift
import AIKit
```

## Verifying Installation

Create a simple test to verify the installation:

```swift
import AIKit

func testInstallation() {
    let provider = MockProvider()
    let model = provider.languageModel("test-model")
    let client = AIKit.client()
    
    print("AIKit installed successfully!")
    print("Provider: \\(provider.name)")
    print("Model: \\(model.modelId)")
}
```

## Next Steps

Now that you have AIKit installed, continue with the [Quick Start Guide](quick-start.md) to build your first AI application.

## Troubleshooting

### Common Issues

#### Swift Version Compatibility
If you encounter Swift version errors, ensure you're using Swift 5.9 or later:

```bash
swift --version
```

#### Platform Requirements
AIKit requires minimum platform versions. Update your deployment targets if needed:

- iOS 13.0+
- macOS 10.15+
- watchOS 6.0+
- tvOS 13.0+

#### Xcode Build Errors
If you encounter build errors in Xcode:

1. Clean build folder: **Product** → **Clean Build Folder**
2. Reset package caches: **File** → **Packages** → **Reset Package Caches**
3. Update packages: **File** → **Packages** → **Update to Latest Package Versions**

### Getting Help

If you're still experiencing issues:

1. Check the [troubleshooting guide](../guides/troubleshooting.md)
2. Search existing [GitHub issues](https://github.com/jcfontecha/ai-kit/issues)
3. Create a new issue with:
   - Your Swift version
   - Your platform/OS version
   - Complete error messages
   - Minimal reproduction code