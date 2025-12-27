# Liquid Glass SwiftUI Implementation Guide

## Introduction

This comprehensive guide provides practical, production-ready SwiftUI implementations of Liquid Glass components. Each example includes complete code, explanations, and best practices from real-world applications.

## Table of Contents

- [Basic Components](#basic-components)
- [Navigation Elements](#navigation-elements)
- [Interactive Controls](#interactive-controls)
- [Input Fields](#input-fields)
- [Floating Actions](#floating-actions)
- [Transitions and Morphing](#transitions-and-morphing)
- [Advanced Patterns](#advanced-patterns)
- [Complete Examples](#complete-examples)

---

## Basic Components

### Simple Glass Button

The most basic glass implementation - a single button with standard glass effect.

```swift
import SwiftUI

struct GlassButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .glassEffect()
    }
}

// Usage
GlassButton(title: "Continue") {
    print("Button tapped")
}
```

**Key Points**:
- Default capsule shape automatically applied
- Glass sits behind text and padding
- No explicit background needed

---

### Glass Card

A content card with glass background.

```swift
struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .glassEffect(in: .rect(cornerRadius: 16))
    }
}

// Usage
GlassCard {
    VStack(alignment: .leading) {
        Text("Title")
            .font(.title2.bold())
        Text("Subtitle")
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
}
```

---

### Tinted Glass Panel

Glass with color tint for improved contrast.

```swift
struct TintedGlassPanel: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Success")
                .font(.headline)
        }
        .padding(32)
        .glassEffect(.regular.tint(tintColor))
    }

    var tintColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.15)
            : .black.opacity(0.05)
    }
}
```

**Adaptive Tinting**: Automatically adjusts for light/dark mode.

---

## Navigation Elements

### Glass Navigation Bar

Custom navigation bar with glass background.

```swift
struct GlassNavigationBar: View {
    let title: String
    let leadingAction: (() -> Void)?
    let trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            // Leading button
            if let leadingAction = leadingAction {
                Button(action: leadingAction) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
            }

            Spacer()

            // Title
            Text(title)
                .font(.headline)

            Spacer()

            // Trailing button
            if let trailingAction = trailingAction {
                Button(action: trailingAction) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            } else {
                // Invisible spacer for symmetry
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .opacity(0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassEffect()
    }
}

// Usage in a view
struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            GlassNavigationBar(
                title: "Messages",
                leadingAction: { print("Back") },
                trailingAction: { print("Menu") }
            )

            ScrollView {
                // Content
            }

            Spacer()
        }
    }
}
```

---

### Glass Tab Bar

Custom bottom tab bar with glass effect.

```swift
struct GlassTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                TabBarItem(
                    icon: "house.fill",
                    title: "Home",
                    isSelected: selectedTab == 0
                ) {
                    selectedTab = 0
                }

                TabBarItem(
                    icon: "magnifyingglass",
                    title: "Search",
                    isSelected: selectedTab == 1
                ) {
                    selectedTab = 1
                }

                TabBarItem(
                    icon: "bell.fill",
                    title: "Notifications",
                    isSelected: selectedTab == 2
                ) {
                    selectedTab = 2
                }

                TabBarItem(
                    icon: "person.fill",
                    title: "Profile",
                    isSelected: selectedTab == 3
                ) {
                    selectedTab = 3
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .glassEffect()
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle()) // Expand tap area
    }
}

// Usage
struct MainView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView().tag(0)
                SearchView().tag(1)
                NotificationsView().tag(2)
                ProfileView().tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            GlassTabBar(selectedTab: $selectedTab)
        }
    }
}
```

---

## Interactive Controls

### Glass Button with Interactive Highlights

Button that responds to touch with glass highlights.

```swift
struct InteractiveGlassButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.headline)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .glassEffect(.regular.interactive())
    }
}

// Usage
InteractiveGlassButton(
    title: "Download",
    icon: "arrow.down.circle.fill",
    action: { print("Downloading...") }
)
```

---

### Glass Toggle

Custom toggle switch with glass styling.

```swift
struct GlassToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.body)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding()
        .glassEffect(.regular.interactive())
    }
}

// Usage
struct SettingsView: View {
    @State private var notificationsEnabled = true

    var body: some View {
        VStack(spacing: 12) {
            GlassToggle(title: "Notifications", isOn: $notificationsEnabled)
            GlassToggle(title: "Location", isOn: .constant(false))
        }
        .padding()
    }
}
```

---

### Glass Segmented Picker

Segmented control with unified glass background.

```swift
struct GlassSegmentedPicker: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                ForEach(options.indices, id: \.self) { index in
                    SegmentButton(
                        title: options[index],
                        isSelected: selection == index
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            selection = index
                        }
                    }
                }
            }
            .padding(4)
        }
        .glassEffect()
    }
}

struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
    }
}

// Usage
struct FilterView: View {
    @State private var selectedFilter = 0

    var body: some View {
        GlassSegmentedPicker(
            options: ["All", "Active", "Completed"],
            selection: $selectedFilter
        )
        .padding()
    }
}
```

---

## Input Fields

### Glass Text Field

Single-line text input with glass background.

```swift
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding()
            .glassEffect(in: .capsule)
    }
}

// Usage
struct FormView: View {
    @State private var email = ""

    var body: some View {
        VStack(spacing: 16) {
            GlassTextField(placeholder: "Email", text: $email)
            GlassTextField(placeholder: "Password", text: .constant(""))
        }
        .padding()
    }
}
```

---

### Glass Search Bar

Search field with search icon and glass styling.

```swift
struct GlassSearchBar: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isFocused)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassEffect()
    }
}

// Usage
struct SearchView: View {
    @State private var searchQuery = ""

    var body: some View {
        VStack {
            GlassSearchBar(searchText: $searchQuery)
                .padding()

            // Search results
            List {
                // ...
            }
        }
    }
}
```

---

### Multiline Chat Input (Complete Example)

Production-ready chat input field with send button.

```swift
struct ChatInputBar: View {
    @Binding var messageText: String
    let onSend: (String) -> Void

    private var isMessageEmpty: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            HStack(alignment: .bottom, spacing: 12) {
                // Multiline text field
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 40)

                // Send button
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            isMessageEmpty
                                ? Color.secondary
                                : Color.accentColor
                        )
                }
                .disabled(isMessageEmpty)
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
        }
        .glassEffect(.regular.tint(.white.opacity(0.1)))
        .animation(.easeInOut(duration: 0.2), value: messageText)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func send() {
        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        onSend(message)
        messageText = ""
    }
}

// Usage
struct ChatView: View {
    @State private var message = ""

    var body: some View {
        VStack {
            // Messages
            ScrollView {
                // Chat messages...
            }

            ChatInputBar(messageText: $message) { message in
                print("Send:", message)
            }
        }
    }
}
```

---

## Floating Actions

### Floating Action Button (FAB)

Circular floating action button with glass effect.

```swift
struct GlassFloatingActionButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
        }
        .glassEffect(in: .circle)
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}

// Usage in a view
struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main content
            ScrollView {
                // ...
            }

            // FAB
            GlassFloatingActionButton(icon: "plus") {
                print("Create new item")
            }
            .padding(24)
        }
    }
}
```

---

### Expandable Floating Actions

FAB that expands into multiple action buttons.

```swift
struct ExpandableGlassFAB: View {
    @Namespace private var glassNS
    @State private var isExpanded = false

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if isExpanded {
                expandedButtons
            } else {
                mainButton
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
    }

    private var mainButton: some View {
        Button(action: { isExpanded.toggle() }) {
            Image(systemName: isExpanded ? "xmark" : "plus")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
        }
        .glassEffect(in: .circle)
        .glassEffectID("fab", in: glassNS)
        .glassEffectTransition(.matchedGeometry)
        .contentTransition(.symbolEffect(.replace))
    }

    private var expandedButtons: some View {
        VStack(spacing: 16) {
            ActionButton(icon: "camera.fill", label: "Camera") {
                print("Camera")
                isExpanded = false
            }

            ActionButton(icon: "photo.fill", label: "Photos") {
                print("Photos")
                isExpanded = false
            }

            ActionButton(icon: "doc.fill", label: "Documents") {
                print("Documents")
                isExpanded = false
            }

            // Close button
            Button(action: { isExpanded = false }) {
                Image(systemName: "xmark")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.secondary))
            }
            .glassEffect(in: .circle)
        }
        .glassEffectID("fab", in: glassNS)
        .glassEffectTransition(.matchedGeometry)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 44, height: 44)
                Text(label)
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
        }
        .glassEffect(.regular.interactive())
    }
}
```

---

## Transitions and Morphing

### Morphing Panel

Button that morphs into an expanded panel.

```swift
struct MorphingGlassPanel: View {
    @Namespace private var morphID
    @State private var isExpanded = false

    var body: some View {
        GlassEffectContainer {
            if isExpanded {
                expandedPanel
            } else {
                collapsedButton
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isExpanded)
    }

    private var collapsedButton: some View {
        Button(action: { isExpanded = true }) {
            HStack {
                Image(systemName: "info.circle")
                Text("Details")
            }
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .glassEffect()
        .glassEffectID("panel", in: morphID)
        .glassEffectTransition(.matchedGeometry)
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Details")
                    .font(.title2.bold())
                Spacer()
                Button(action: { isExpanded = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore.")
                .font(.body)

            HStack {
                Button("Action 1") { }
                    .buttonStyle(.borderedProminent)
                Button("Action 2") { }
                    .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .frame(width: 320)
        .glassEffect(in: .rect(cornerRadius: 20))
        .glassEffectID("panel", in: morphID)
        .glassEffectTransition(.matchedGeometry)
    }
}
```

---

### Like Button with State Transition

Interactive button with smooth icon morphing.

```swift
struct LikeButton: View {
    @State private var isLiked = false

    var body: some View {
        Button(action: { isLiked.toggle() }) {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundColor(isLiked ? .red : .primary)
                .frame(width: 50, height: 50)
        }
        .glassEffect(.regular.interactive())
        .contentTransition(.symbolEffect(.replace))
        .animation(.spring(response: 0.3), value: isLiked)
    }
}
```

---

## Advanced Patterns

### Glass Text Effect (Custom Shapes)

Creating glass effect in the shape of text glyphs.

```swift
import CoreText

struct GlassTextShape: Shape {
    let text: String
    let font: UIFont

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let attributedString = NSAttributedString(
            string: text,
            attributes: [.font: font]
        )

        let line = CTLineCreateWithAttributedString(attributedString)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)

            CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, 0), &positions)

            for (glyph, position) in zip(glyphs, positions) {
                if let glyphPath = CTFontCreatePathForGlyph(font, glyph, nil) {
                    var transform = CGAffineTransform(translationX: position.x, y: position.y)
                    path.addPath(Path(glyphPath), transform: transform)
                }
            }
        }

        return path
    }
}

struct GlassTextView: View {
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.blue, .purple, .pink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glass text
            GlassTextShape(
                text: "GLASS",
                font: UIFont.systemFont(ofSize: 72, weight: .black)
            )
            .fill(Color.clear)
            .glassEffect(.regular.tint(.white.opacity(0.3)))
            .frame(height: 100)
        }
    }
}
```

---

### Grouped Glass Buttons with Union

Multiple buttons sharing one continuous glass background.

```swift
struct GlassButtonToolbar: View {
    @Namespace private var glassNS

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            VStack(spacing: 0) {
                ToolbarButton(icon: "square.and.arrow.up", title: "Share")
                    .glassEffect()
                    .glassEffectUnion(id: "toolbar", namespace: glassNS)

                Divider()
                    .padding(.horizontal)

                ToolbarButton(icon: "heart", title: "Like")
                    .glassEffect()
                    .glassEffectUnion(id: "toolbar", namespace: glassNS)

                Divider()
                    .padding(.horizontal)

                ToolbarButton(icon: "bookmark", title: "Save")
                    .glassEffect()
                    .glassEffectUnion(id: "toolbar", namespace: glassNS)
            }
            .frame(width: 200)
        }
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String

    var body: some View {
        Button(action: { print(title) }) {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
            }
            .padding()
        }
        .foregroundColor(.primary)
    }
}
```

---

## Complete Examples

### Glass Quote Card (Full Implementation)

Production-ready quote card component.

```swift
struct GlassQuoteCard: View {
    let quote: String
    let author: String
    @State private var isLiked = false
    @State private var isSaved = false

    var body: some View {
        ZStack {
            // Background
            backgroundImage

            // Quote card
            VStack(spacing: 24) {
                Spacer()

                quoteContent

                actionButtons

                Spacer()
            }
            .padding()
        }
    }

    private var backgroundImage: some View {
        Image("background") // Your background image
            .resizable()
            .aspectRatio(contentMode: .fill)
            .ignoresSafeArea()
    }

    private var quoteContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.title)
                .foregroundColor(.secondary)

            Text(quote)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            Text("— \(author)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(32)
        .glassEffect(.regular.tint(.white.opacity(0.1)))
    }

    private var actionButtons: some View {
        HStack(spacing: 20) {
            ActionIcon(
                icon: isLiked ? "heart.fill" : "heart",
                isActive: isLiked
            ) {
                withAnimation(.spring(response: 0.3)) {
                    isLiked.toggle()
                }
            }

            ActionIcon(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                isActive: isSaved
            ) {
                withAnimation(.spring(response: 0.3)) {
                    isSaved.toggle()
                }
            }

            ActionIcon(icon: "square.and.arrow.up", isActive: false) {
                print("Share")
            }
        }
    }
}

struct ActionIcon: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isActive ? .accentColor : .primary)
                .frame(width: 50, height: 50)
        }
        .glassEffect(.regular.interactive())
        .contentTransition(.symbolEffect(.replace))
    }
}

// Usage
GlassQuoteCard(
    quote: "The only way to do great work is to love what you do.",
    author: "Steve Jobs"
)
```

---

### Glass Settings List

Complete settings screen with glass components.

```swift
struct GlassSettingsView: View {
    @State private var notificationsEnabled = true
    @State private var darkModeEnabled = false
    @State private var selectedTheme = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile section
                    profileSection

                    // Preferences
                    preferencesSection

                    // Theme picker
                    themeSection

                    // Sign out
                    signOutButton
                }
                .padding()
            }
            .navigationTitle("Settings")
        }
    }

    private var profileSection: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.accentColor.gradient)
                .frame(width: 60, height: 60)
                .overlay {
                    Text("JD")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading) {
                Text("John Doe")
                    .font(.headline)
                Text("john@example.com")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private var preferencesSection: some View {
        VStack(spacing: 12) {
            GlassToggle(title: "Notifications", isOn: $notificationsEnabled)
            GlassToggle(title: "Dark Mode", isOn: $darkModeEnabled)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Theme")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            GlassSegmentedPicker(
                options: ["System", "Light", "Dark"],
                selection: $selectedTheme
            )
        }
    }

    private var signOutButton: some View {
        Button(action: { print("Sign out") }) {
            Text("Sign Out")
                .font(.headline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .glassEffect(.regular.interactive())
    }
}
```

---

## Accessibility Considerations

### Reduce Transparency Support

All examples should respect accessibility settings:

```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency

var glassModifier: some View {
    if reduceTransparency {
        Color(.systemBackground).opacity(0.95)
    } else {
        Color.clear.glassEffect()
    }
}
```

---

### VoiceOver Labels

Ensure interactive glass elements have proper labels:

```swift
Button(action: share) {
    Image(systemName: "square.and.arrow.up")
        .frame(width: 44, height: 44)
}
.glassEffect(.regular.interactive())
.accessibilityLabel("Share")
.accessibilityHint("Opens share sheet")
```

---

## Testing on Device

Always test glass implementations on physical devices:

1. **Light/Dark Mode**: Verify appearance in both modes
2. **Different Backgrounds**: Test against various content
3. **Performance**: Check frame rate with Instruments
4. **Accessibility**: Enable Reduce Transparency and test
5. **Dynamic Type**: Test with larger text sizes

---

## Sources

- [Apple Developer Documentation - Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [GitHub - LiquidGlassSwiftUI Sample](https://github.com/mertozseven/LiquidGlassSwiftUI)
- [WWDC25 - Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Fatbobman - Grow on iOS 26](https://fatbobman.com/en/posts/grow-on-ios26)
- [Create with Swift - Exploring Liquid Glass](https://www.createwithswift.com/exploring-a-new-visual-language-liquid-glass/)
