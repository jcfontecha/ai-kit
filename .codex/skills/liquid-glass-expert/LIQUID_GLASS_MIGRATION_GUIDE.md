# Liquid Glass Migration and Compatibility Guide

## Introduction

This guide helps you migrate existing iOS applications to adopt Liquid Glass design in iOS 26+, covering compatibility considerations, migration strategies, and fallback approaches for older iOS versions.

## Table of Contents

- [Quick Start Migration](#quick-start-migration)
- [Automatic Adoption](#automatic-adoption)
- [Manual Migration Strategies](#manual-migration-strategies)
- [Backward Compatibility](#backward-compatibility)
- [Temporary Opt-Out](#temporary-opt-out)
- [Testing and Validation](#testing-and-validation)
- [Common Migration Patterns](#common-migration-patterns)
- [Cross-Platform Considerations](#cross-platform-considerations)

---

## Quick Start Migration

### Minimum Changes Required

For apps already using standard system components, minimal changes are needed:

```swift
// iOS 25 and earlier
class MyViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Already using standard UINavigationBar
    }
}

// iOS 26+
// Simply recompile with iOS 26 SDK
// Navigation bar automatically gets Liquid Glass!
```

**Key Point**: Standard navigation bars, tab bars, and toolbars automatically adopt Liquid Glass when compiled with iOS 26 SDK.

---

## Automatic Adoption

### What Gets Liquid Glass Automatically

When you compile your app with iOS 26 SDK, these system components automatically adopt Liquid Glass:

#### SwiftUI
- `NavigationStack` / `NavigationSplitView`
- `TabView`
- `.toolbar` modifier contents
- `.searchable()` search fields
- Standard buttons with `.bordered` or `.borderedProminent` styles
- `List` headers/footers (on scroll)

#### UIKit
- `UINavigationBar`
- `UITabBar`
- `UIToolbar`
- `UISearchBar`
- `UIBarButtonItem` groups
- `UIVisualEffectView` with blur effects (upgraded to glass)

### Before Migration
```swift
// iOS 25: Using UIBlurEffect
let blurEffect = UIBlurEffect(style: .systemMaterial)
let blurView = UIVisualEffectView(effect: blurEffect)
```

### After Compilation with iOS 26 SDK
```swift
// Same code, but automatically enhanced!
let blurEffect = UIBlurEffect(style: .systemMaterial)
let blurView = UIVisualEffectView(effect: blurEffect)
// This now renders with Liquid Glass characteristics
```

---

## Manual Migration Strategies

### Strategy 1: Progressive Enhancement

Adopt Liquid Glass incrementally, starting with high-impact areas.

#### Phase 1: System Components (Day 1)
```swift
// Just recompile - automatic!
```

#### Phase 2: Custom Overlays (Week 1)
```swift
// Replace custom blur views
// Before (iOS 25)
let customBackground = UIView()
customBackground.backgroundColor = .systemBackground.withAlphaComponent(0.8)

// After (iOS 26+)
if #available(iOS 26.0, *) {
    let glassEffect = UIGlassEffect(style: .regular)
    let glassView = UIVisualEffectView(effect: glassEffect)
    // Use glassView
} else {
    // Keep old implementation
}
```

#### Phase 3: Custom Controls (Week 2-3)
Migrate buttons, input fields, and cards to glass styling.

#### Phase 4: Advanced Patterns (Week 4+)
Implement morphing transitions, glass containers, and complex interactions.

---

### Strategy 2: Feature Flag Approach

Use feature flags to gradually roll out Liquid Glass.

```swift
enum FeatureFlags {
    static var useLiquidGlass: Bool {
        // Can be controlled remotely or via Settings
        UserDefaults.standard.bool(forKey: "enable_liquid_glass")
    }
}

// Usage
func createBackground() -> UIView {
    if #available(iOS 26.0, *), FeatureFlags.useLiquidGlass {
        let glassEffect = UIGlassEffect(style: .regular)
        return UIVisualEffectView(effect: glassEffect)
    } else {
        // Fallback implementation
        return createLegacyBackground()
    }
}
```

---

## Backward Compatibility

### Supporting iOS 25 and Earlier

#### SwiftUI Compatibility

```swift
struct GlassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .padding()
        }
        .background(glassBackground)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect()
        } else {
            Color.clear.background(.regularMaterial)
        }
    }
}
```

#### UIKit Compatibility

```swift
class GlassView: UIView {
    private var effectView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBackground()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBackground()
    }

    private func setupBackground() {
        let effect: UIVisualEffect

        if #available(iOS 26.0, *) {
            effect = UIGlassEffect(style: .regular)
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }

        let view = UIVisualEffectView(effect: effect)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)

        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        effectView = view
    }

    var contentView: UIView {
        effectView?.contentView ?? self
    }
}
```

---

### Deployment Target Strategy

#### Recommended Approach
Set minimum deployment target to iOS 18.0, with runtime checks for iOS 26 features:

```swift
// In project settings:
// iOS Deployment Target: 18.0

// In code:
if #available(iOS 26.0, *) {
    // Use Liquid Glass
} else {
    // Use compatible alternative
}
```

#### Multi-Target Build

For apps supporting very old iOS versions:

```swift
#if compiler(>=6.0)
    #if available(iOS 26.0, *)
        // Liquid Glass implementation
    #else
        // iOS 18-25 implementation
    #endif
#else
    // Legacy Swift compiler implementation
#endif
```

---

## Temporary Opt-Out

### When to Use Opt-Out

Use the compatibility flag temporarily when:
- App has custom visual styling that conflicts with Liquid Glass
- Complex blur overlays need redesign
- Need time to test thoroughly before public release
- Gradual rollout to users

### Adding the Compatibility Flag

**Info.plist:**
```xml
<key>UIDesignRequiresCompatibility</key>
<true/>
```

**Swift Code:**
```swift
// In AppDelegate or Scene configuration
if Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool == true {
    print("Running in compatibility mode - Liquid Glass disabled")
}
```

### Consequences of Opt-Out

When compatibility mode is enabled:
- All system bars revert to iOS 25 appearance
- `UIGlassEffect` unavailable (calls will fail)
- `.glassEffect()` modifier has no effect
- Tab bars don't minimize on scroll
- Search bars use old placement
- Badge API on bar buttons unavailable

**Warning**: Apple may remove this flag in future SDK versions. It's temporary only.

---

## Testing and Validation

### Testing Checklist

#### Visual Testing
- [ ] Light mode appearance
- [ ] Dark mode appearance
- [ ] Different backgrounds (images, colors, gradients)
- [ ] Reduce Transparency enabled
- [ ] Increase Contrast enabled
- [ ] Various Dynamic Type sizes

#### Functional Testing
- [ ] Touch interactions (highlights work)
- [ ] Animations (morphing transitions smooth)
- [ ] Scrolling performance (no lag with glass overlays)
- [ ] Keyboard appearance (glass adjusts correctly)
- [ ] Orientation changes

#### Platform Testing
- [ ] iPhone (all sizes)
- [ ] iPad (all sizes, split view, slide over)
- [ ] Mac Catalyst (if applicable)
- [ ] Apple TV (if applicable)
- [ ] Apple Watch (if applicable)

---

### Automated Testing

#### Snapshot Tests

```swift
import SnapshotTesting

class GlassViewTests: XCTestCase {
    func testGlassButtonAppearance() {
        let button = GlassButton(title: "Test")

        // Test on light background
        assertSnapshot(matching: button, as: .image)

        // Test on dark background
        button.overrideUserInterfaceStyle = .dark
        assertSnapshot(matching: button, as: .image)
    }

    func testAccessibilityMode() {
        // Test with Reduce Transparency
        let button = GlassButton(title: "Test")
        button.accessibilityReduceTransparency = true
        assertSnapshot(matching: button, as: .image)
    }
}
```

---

### Performance Testing

#### Measuring Glass Effect Performance

```swift
import XCTest

class GlassPerformanceTests: XCTestCase {
    func testGlassRenderingPerformance() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()]) {
            let view = createViewWithManyGlassElements()
            view.layoutIfNeeded()
        }
    }

    private func createViewWithManyGlassElements() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))

        for i in 0..<10 {
            if #available(iOS 26.0, *) {
                let glassView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
                glassView.frame = CGRect(x: 0, y: CGFloat(i * 60), width: 375, height: 50)
                container.addSubview(glassView)
            }
        }

        return container
    }
}
```

**Expected Results**:
- Render time: < 16ms per frame (60fps)
- Memory: < 50MB increase with 10 glass elements
- CPU: < 20% sustained usage

---

## Common Migration Patterns

### Pattern 1: Custom Blur to Glass

**Before (iOS 25):**
```swift
class CustomBlurView: UIView {
    private let blurView: UIVisualEffectView

    init() {
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        super.init(frame: .zero)
        setupViews()
    }

    private func setupViews() {
        addSubview(blurView)
        // Layout...
    }
}
```

**After (iOS 26+):**
```swift
class CustomGlassView: UIView {
    private let effectView: UIVisualEffectView

    init() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = .systemBackground.withAlphaComponent(0.1)
            effectView = UIVisualEffectView(effect: glassEffect)
        } else {
            effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        }

        super.init(frame: .zero)
        setupViews()
    }

    private func setupViews() {
        addSubview(effectView)
        // Layout...
    }
}
```

---

### Pattern 2: Material Backgrounds to Glass (SwiftUI)

**Before:**
```swift
struct Card: View {
    var body: some View {
        VStack {
            Text("Content")
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}
```

**After:**
```swift
struct Card: View {
    var body: some View {
        VStack {
            Text("Content")
        }
        .padding()
        .background(cardBackground)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(in: .rect(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        }
    }
}
```

---

### Pattern 3: Custom Navigation Bar

**Before:**
```swift
class CustomNavBar: UIView {
    private let backgroundView = UIView()

    private func setupBackground() {
        backgroundView.backgroundColor = .systemBackground.withAlphaComponent(0.8)
        // Add blur manually...
    }
}
```

**After:**
```swift
class CustomNavBar: UIView {
    private let backgroundView: UIView

    init() {
        if #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            backgroundView = UIVisualEffectView(effect: glassEffect)
        } else {
            let blur = UIBlurEffect(style: .systemMaterial)
            backgroundView = UIVisualEffectView(effect: blur)
        }

        super.init(frame: .zero)
        setupViews()
    }

    private func setupViews() {
        addSubview(backgroundView)
        // Layout...
    }
}
```

---

## Cross-Platform Considerations

### React Native

Liquid Glass is **not directly accessible** in React Native. Options:

#### Option 1: Native Modules
```javascript
// JavaScript
import { NativeModules } from 'react-native';
const { GlassViewManager } = NativeModules;

// Native Swift module
@objc(GlassViewManager)
class GlassViewManager: NSObject {
    @objc
    static func requiresMainQueueSetup() -> Bool {
        return true
    }

    @objc
    func createGlassView() {
        if #available(iOS 26.0, *) {
            // Create and return glass view
        }
    }
}
```

#### Option 2: Native Components
Use `requireNativeComponent` to wrap glass views.

---

### Flutter

Flutter's Skia rendering engine **cannot reproduce** Liquid Glass effects. Options:

#### Option 1: Platform Views
```dart
// Embed native UIKit glass view
import 'package:flutter/services.dart';

class GlassView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: 'glass-view',
        creationParams: {},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return Container(); // Fallback
  }
}
```

#### Option 2: Approximation
```dart
// Approximate with BackdropFilter (not true Liquid Glass)
BackdropFilter(
  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
  child: Container(
    color: Colors.white.withOpacity(0.2),
  ),
)
```

---

### Xamarin / .NET MAUI

Use platform-specific handlers:

```csharp
#if IOS
[assembly: ExportRenderer(typeof(GlassView), typeof(GlassViewRenderer))]
namespace MyApp.iOS
{
    public class GlassViewRenderer : ViewRenderer
    {
        protected override void OnElementChanged(ElementChangedEventArgs<View> e)
        {
            base.OnElementChanged(e);

            if (Control == null && e.NewElement != null)
            {
                if (UIDevice.CurrentDevice.CheckSystemVersion(26, 0))
                {
                    var glassEffect = new UIGlassEffect(UIGlassEffectStyle.Regular);
                    var glassView = new UIVisualEffectView(glassEffect);
                    SetNativeControl(glassView);
                }
            }
        }
    }
}
#endif
```

---

## Migration Timeline Example

### 3-Month Migration Plan

**Month 1: Preparation**
- Week 1: Update Xcode to latest version
- Week 2: Compile with iOS 26 SDK, enable compatibility mode
- Week 3: Audit existing blur/material usage
- Week 4: Design glass implementation strategy

**Month 2: Implementation**
- Week 1: Migrate high-traffic screens
- Week 2: Migrate custom controls
- Week 3: Implement morphing transitions
- Week 4: Performance optimization

**Month 3: Rollout**
- Week 1: Internal testing
- Week 2: Beta testing (TestFlight)
- Week 3: Staged rollout (10% → 50% → 100%)
- Week 4: Monitor metrics, fix issues

---

## Rollback Plan

### Quick Rollback Strategy

If issues arise post-migration:

#### Emergency Fix
```swift
// Add to Info.plist immediately
<key>UIDesignRequiresCompatibility</key>
<true/>

// Or use remote config
class AppConfig {
    static var forceCompatibilityMode: Bool {
        // Fetch from server
        RemoteConfig.shared.bool(forKey: "force_compatibility_mode")
    }
}

// In AppDelegate
if AppConfig.forceCompatibilityMode {
    // Force old appearance
}
```

#### Version-Based Rollback
```swift
// Target specific app versions
let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

if currentVersion == "2.0.0" {
    // Problematic version - use compatibility mode
}
```

---

## Post-Migration Monitoring

### Key Metrics to Track

1. **Crash Rate**: Monitor for glass-related crashes
2. **Performance**: Track frame rates, memory usage
3. **User Feedback**: Collect feedback on new design
4. **Accessibility**: Monitor usage of Reduce Transparency setting

### Analytics Events

```swift
enum AnalyticsEvent {
    case glassEffectRendered(component: String)
    case glassPerformanceIssue(fps: Double)
    case accessibilityOverride(setting: String)
}

// Track usage
Analytics.log(.glassEffectRendered(component: "bottom_sheet"))
```

---

## Conclusion

Liquid Glass adoption is straightforward for most apps:

1. **Recompile** with iOS 26 SDK for automatic adoption
2. **Test thoroughly** on devices with various backgrounds
3. **Migrate custom views** progressively
4. **Use fallbacks** for iOS 25 and earlier
5. **Monitor** performance and user feedback

**Most Important**: Start small, test often, and iterate based on user feedback.

---

## Sources

- [Apple Developer Documentation - Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Fatbobman - Grow on iOS 26 - Migration Experience](https://fatbobman.com/en/posts/grow-on-ios26)
- [WWDC25 Session - Migrate to the new design](https://developer.apple.com/videos/play/wwdc2025/)
- [Apple Newsroom - New Software Design](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
