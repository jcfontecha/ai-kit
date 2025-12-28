---
name: xcb-config
description: Configure xcb.json to map Xcode schemes to workspaces/projects for building with xcb
---

# xcb Configuration Guide

xcb is a CLI wrapper around xcodebuild. The `xcb.json` file maps scheme names to their containers (workspace, project, or Swift package).

## Config Structure

```json
{
  "version": 1,
  "builds": [
    {
      "id": "optional-identifier",
      "scheme": "SchemeName",
      "workspace": "Path/To/App.xcworkspace",
      "destination": "platform=iOS Simulator,name=iPhone 15",
      "configuration": "Debug"
    }
  ]
}
```

## Build Entry Fields

| Field | Required | Description |
|-------|----------|-------------|
| `scheme` | Yes | Xcode scheme name (must match exactly) |
| `workspace` | One of these | Path to `.xcworkspace` file |
| `project` | required | Path to `.xcodeproj` file |
| `packageDir` | | Path to Swift package directory |
| `id` | No | Identifier for the build entry |
| `destination` | No | xcodebuild destination string |
| `configuration` | No | Build configuration (Debug/Release) |
| `sdk` | No | SDK name (iphonesimulator, iphoneos, macosx) |

## Common Destinations

- iOS Simulator: `"platform=iOS Simulator,name=iPhone 15"`
- Generic iOS: `"generic/platform=iOS"`
- macOS: `"platform=macOS"`
- watchOS Simulator: `"platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)"`

## How to Configure

1. Run `xcb schemes` to list available schemes from the workspace/project
2. For each scheme you want to build, add a build entry with:
   - The exact `scheme` name
   - The `workspace` or `project` path containing that scheme
   - Optional `destination` and `configuration`

## Example: App with SPM Dependencies

```json
{
  "version": 1,
  "builds": [
    {
      "id": "app",
      "scheme": "MyApp",
      "workspace": "MyApp.xcworkspace",
      "destination": "platform=iOS Simulator,name=iPhone 15",
      "configuration": "Debug"
    },
    {
      "id": "tests",
      "scheme": "MyAppTests",
      "workspace": "MyApp.xcworkspace",
      "destination": "platform=iOS Simulator,name=iPhone 15",
      "configuration": "Debug"
    }
  ]
}
```

## Example: Swift Package

```json
{
  "version": 1,
  "builds": [
    {
      "scheme": "MyLibrary",
      "packageDir": ".",
      "destination": "generic/platform=iOS"
    }
  ]
}
```

## Usage After Configuration

```bash
xcb MyApp          # Build the MyApp scheme
xcb MyAppTests     # Build the test scheme
xcb schemes        # List all available schemes
```