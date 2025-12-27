# Liquid Glass API Reference

## Overview

Liquid Glass is Apple's dynamic material system introduced in iOS 26, iPadOS 26, macOS 26 (Tahoe), watchOS 26, and tvOS 26. It provides a translucent, physics-based UI material that reflects and refracts surrounding content, creating depth-aware, interactive interfaces.

This document provides a comprehensive reference of all public APIs for implementing Liquid Glass in iOS applications.

## Table of Contents

- [SwiftUI APIs](#swiftui-apis)
- [UIKit APIs](#uikit-apis)
- [Platform Availability](#platform-availability)
- [Related Types](#related-types)

---

## SwiftUI APIs

### View Modifiers

#### `glassEffect(_:in:isEnabled:)`

Applies a Liquid Glass material effect to a view.

```swift
func glassEffect(
    _ style: GlassStyle = .regular,
    in shape: GlassShape? = nil,
    isEnabled: Bool = true
) -> some View
```

**Parameters:**
- `style`: The glass style to apply. Default is `.regular`.
- `shape`: Optional shape for the glass backdrop. Default is capsule.
- `isEnabled`: Boolean to toggle the effect. Default is `true`.

**Example:**
```swift
Text("Hello")
    .padding()
    .glassEffect() // Default regular glass in capsule shape
```

**Glass Style Modifiers:**

```swift
// Tinted glass
.glassEffect(.regular.tint(.orange))

// Interactive glass (responds to touch)
.glassEffect(.regular.interactive())

// Combined
.glassEffect(.regular.tint(.white.opacity(0.3)).interactive())
```

**Custom Shapes:**

```swift
// Rounded rectangle
.glassEffect(in: .rect(cornerRadius: 16))

// Circle
.glassEffect(in: .circle)

// Capsule (default)
.glassEffect(in: .capsule)
```

---

#### `glassEffectUnion(id:namespace:)`

Merges separate glass elements into one unified shape based on a shared ID.

```swift
func glassEffectUnion(
    id: String,
    namespace: Namespace.ID
) -> some View
```

**Parameters:**
- `id`: Unique identifier for the glass union group
- `namespace`: Namespace for scoping the union ID

**Requirements:**
- Views must share the same ID and namespace
- Views must use compatible glass styles and tints
- Views should be within a `GlassEffectContainer`

**Example:**
```swift
@Namespace var glassNS

GlassEffectContainer {
    VStack {
        Button("Top", action: {})
            .glassEffect()
            .glassEffectUnion(id: "toolbar", namespace: glassNS)

        Button("Bottom", action: {})
            .glassEffect()
            .glassEffectUnion(id: "toolbar", namespace: glassNS)
    }
}
// Creates one continuous glass shape covering both buttons
```

---

#### `glassEffectID(_:in:)`

Tags a glass effect for matched transition animations between view states.

```swift
func glassEffectID(
    _ id: AnyHashable,
    in namespace: Namespace.ID
) -> some View
```

**Parameters:**
- `id`: Hashable identifier for the glass effect
- `namespace`: Namespace for coordinating transitions

**Use Case:**
Enables smooth morphing transitions when glass elements appear/disappear or change shape during state changes.

**Example:**
```swift
@Namespace var ns
@State private var expanded = false

if expanded {
    RoundedRectangle(cornerRadius: 20)
        .frame(width: 300, height: 200)
        .glassEffect()
        .glassEffectID("panel", in: ns)
        .glassEffectTransition(.matchedGeometry)
} else {
    Circle()
        .frame(width: 60, height: 60)
        .glassEffect()
        .glassEffectID("panel", in: ns)
        .glassEffectTransition(.matchedGeometry)
}
```

---

#### `glassEffectTransition(_:)`

Specifies the transition animation type for glass shape changes.

```swift
func glassEffectTransition(_ transition: GlassEffectTransition) -> some View
```

**Available Transitions:**
- `.matchedGeometry`: Morphs glass shape between states
- `.materialize`: Fades/materializes glass appearance

**Example:**
```swift
.glassEffect()
.glassEffectTransition(.matchedGeometry)
```

---

### Container Views

#### `GlassEffectContainer`

Groups multiple glass-affected views for unified rendering and morphing behavior.

```swift
struct GlassEffectContainer<Content: View>: View {
    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content)
}
```

**Parameters:**
- `spacing`: Threshold distance for glass blob merging. Glass elements closer than this value will merge into one shape.
- `content`: ViewBuilder containing glass-affected views

**Benefits:**
- Improved rendering performance (single GPU composite)
- Automatic morphing between adjacent glass elements
- Unified light reflection and refraction across grouped elements

**Example:**
```swift
GlassEffectContainer(spacing: 20) {
    HStack {
        Button("Edit", action: {}).glassEffect()
        Button("Share", action: {}).glassEffect()
        Button("Delete", action: {}).glassEffect()
    }
}
// Buttons will merge into one glass shape if closer than 20 points
```

**Single Background Pattern:**
```swift
GlassEffectContainer {
    HStack {
        TextField("Search", text: $query)
        Button("Send", action: {})
    }
    .padding()
}
.glassEffect() // Applied to container = single glass background
```

---

### Button Styles

#### `.glass`

Standard translucent glass button style.

```swift
ButtonStyle.glass
```

**Example:**
```swift
Button("OK", action: {})
    .buttonStyle(.glass)
```

#### `.glassProminent`

Prominent glass button with increased opacity and tint.

```swift
ButtonStyle.glassProminent
```

**Example:**
```swift
Button("Submit", action: {})
    .buttonStyle(.glassProminent)
    .tint(.blue)
```

---

### Toolbar APIs

#### `DefaultToolbarItem`

System-provided toolbar item with native glass styling.

```swift
struct DefaultToolbarItem {
    init(kind: DefaultToolbarItemKind, placement: ToolbarItemPlacement)
}
```

**Available Kinds:**
- `.search`: Search field
- `.cancellationAction`: Cancel button
- Other system-defined items

**Example:**
```swift
.toolbar {
    DefaultToolbarItem(kind: .search, placement: .bottomBar)
}
```

---

#### `ToolbarSpacer`

Flexible or fixed spacing for toolbar layouts.

```swift
struct ToolbarSpacer {
    init(_ space: ToolbarSpacerType, placement: ToolbarItemPlacement)
}
```

**Space Types:**
- `.flexible`: Expands to fill available space
- `.fixed(CGFloat)`: Fixed-width spacing

**Example:**
```swift
.toolbar {
    ToolbarSpacer(.flexible, placement: .bottomBar)
    ToolbarItem(placement: .bottomBar) {
        Button("Action", action: {})
    }
}
```

---

### Search Modifiers

#### `searchToolbarBehavior(_:)`

Controls search field presentation behavior.

```swift
func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View
```

**Behaviors:**
- `.minimize`: Search appears as compact icon, expands on tap
- `.automatic`: System chooses based on context

**Example:**
```swift
NavigationStack {
    ContentView()
}
.searchable(text: $searchText)
.searchToolbarBehavior(.minimize)
```

---

## UIKit APIs

### UIGlassEffect

`UIGlassEffect` is a `UIVisualEffect` subclass for applying Liquid Glass material in UIKit.

```swift
class UIGlassEffect: UIVisualEffect {
    init(style: UIGlassEffect.Style)

    var tintColor: UIColor?
    var isInteractive: Bool
}
```

#### Styles

```swift
enum UIGlassEffect.Style {
    case regular  // Standard translucent glass with blur
    case clear    // Transparent glass with highlights only
}
```

#### Properties

- **`tintColor`**: Optional color tint for the glass effect
- **`isInteractive`**: Enables touch-responsive highlights and animations

#### Usage

```swift
// Basic glass effect
let glassEffect = UIGlassEffect(style: .regular)
let glassView = UIVisualEffectView(effect: glassEffect)
glassView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
glassView.layer.cornerRadius = 12
glassView.layer.masksToBounds = true
view.addSubview(glassView)

// Tinted interactive glass
let tintedGlass = UIGlassEffect(style: .regular)
tintedGlass.tintColor = .systemBlue.withAlphaComponent(0.3)
tintedGlass.isInteractive = true
let tintedView = UIVisualEffectView(effect: tintedGlass)

// Animated effect change
UIView.animate(withDuration: 0.3) {
    glassView.effect = UIGlassEffect(style: .clear)
}
```

---

### UIGlassContainerEffect

Groups multiple glass effect views for coordinated rendering.

```swift
class UIGlassContainerEffect: UIVisualEffect {
    var spacing: CGFloat
}
```

#### Usage

```swift
let containerEffect = UIGlassContainerEffect()
containerEffect.spacing = 20

let containerView = UIVisualEffectView(effect: containerEffect)

let glass1 = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
let glass2 = UIVisualEffectView(effect: UIGlassEffect(style: .regular))

containerView.contentView.addSubview(glass1)
containerView.contentView.addSubview(glass2)
```

---

### UIBarButtonItem Enhancements

#### Badge Property

Display badges on bar button items.

```swift
var badge: UIBarButtonItem.Badge?
```

**Badge Types:**

```swift
enum UIBarButtonItem.Badge {
    case count(Int)
    case text(String)
}
```

**Example:**

```swift
let folderButton = UIBarButtonItem(
    image: UIImage(systemName: "folder"),
    style: .plain,
    target: self,
    action: #selector(openFolder)
)
folderButton.badge = .count(5)

// Remove badge
folderButton.badge = nil
```

---

### UIButton Configuration

#### Glass Button Styles

```swift
// Standard glass button
button.configuration = .glass()

// Prominent glass button
button.configuration = .prominentGlass()
```

---

### UITabBarController

#### Tab Bar Minimize Behavior

```swift
enum UITabBarController.MinimizeBehavior {
    case never
    case onScrollDown
    case automatic
}

var tabBarMinimizeBehavior: UITabBarController.MinimizeBehavior
```

**Example:**

```swift
tabBarController.tabBarMinimizeBehavior = .onScrollDown
```

#### Tab Accessories

```swift
class UITabAccessory {
    init(contentView: UIView)
}

var bottomAccessory: UITabAccessory?
var topAccessory: UITabAccessory?
```

**Example:**

```swift
let nowPlayingView = NowPlayingView()
let accessory = UITabAccessory(contentView: nowPlayingView)
tabBarController.bottomAccessory = accessory
```

---

### UINavigationItem

#### Search Bar Integration

```swift
var searchBarPlacementAllowsExternalIntegration: Bool
```

Enables SearchBar in toolbars and navigation bars with glass styling.

**Example:**

```swift
navigationItem.searchBarPlacementAllowsExternalIntegration = true
```

---

### UIBarButtonItem Spacing

#### Fixed Space

```swift
class func fixedSpace(_ width: CGFloat) -> UIBarButtonItem
```

**Example:**

```swift
navigationItem.rightBarButtonItems = [
    doneButton,
    flagButton,
    .fixedSpace(0),
    shareButton
]
```

---

## Platform Availability

All Liquid Glass APIs require:

- **iOS**: 26.0+
- **iPadOS**: 26.0+
- **macOS**: 26.0+ (Tahoe)
- **watchOS**: 26.0+
- **tvOS**: 26.0+
- **visionOS**: Not applicable (uses different material system)

### Availability Checks

```swift
if #available(iOS 26.0, macOS 26.0, *) {
    view.glassEffect()
} else {
    // Fallback to .regularMaterial or solid color
    view.background(.regularMaterial)
}
```

### Backward Compatibility

For apps supporting iOS 25 and earlier:

```swift
#if available(iOS 26.0, *)
let effect = UIGlassEffect(style: .regular)
#else
let effect = UIBlurEffect(style: .systemMaterial)
#endif
```

---

## Related Types

### GlassStyle

```swift
struct GlassStyle {
    static var regular: GlassStyle

    func tint(_ color: Color) -> GlassStyle
    func interactive() -> GlassStyle
}
```

### GlassShape

```swift
enum GlassShape {
    case capsule
    case circle
    case rect(cornerRadius: CGFloat)
}
```

### GlassEffectTransition

```swift
enum GlassEffectTransition {
    case matchedGeometry
    case materialize
}
```

---

## Compatibility Flag

### Opting Out (Temporary)

For apps not ready for Liquid Glass, add to Info.plist:

```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```

**Warning:** This flag is temporary and will be removed in future SDK versions. It disables Liquid Glass system-wide in your app, reverting to iOS 25 appearance.

---

## Performance Considerations

### GPU Acceleration

Liquid Glass effects are GPU-accelerated via Metal but are rendering-intensive. Best practices:

- Limit number of simultaneous glass effects
- Use `GlassEffectContainer` to group nearby glass elements
- Avoid stacking multiple independent glass layers
- Test on actual devices, not just simulators

### Memory Impact

Each glass effect maintains additional rendering buffers for:
- Real-time blur computation
- Reflection mapping
- Specular highlights
- Interactive response tracking

Monitor memory usage with Instruments when implementing extensive glass UIs.

---

## Sources

- [Apple Developer Documentation - Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple Developer Documentation - Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [WWDC25 - Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Appcircle Blog - WWDC25: Build a UIKit App with Liquid Glass Design](https://appcircle.io/blog/wwdc25-build-a-uikit-app-with-the-new-liquid-glass-design)
- [GitHub - LiquidGlassSwiftUI Sample](https://github.com/mertozseven/LiquidGlassSwiftUI)
- [Create with Swift - Exploring Liquid Glass](https://www.createwithswift.com/exploring-a-new-visual-language-liquid-glass/)
