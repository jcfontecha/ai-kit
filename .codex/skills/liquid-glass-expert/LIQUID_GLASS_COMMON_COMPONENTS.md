# Liquid Glass Common Components and Use Cases

## Introduction

This document provides a library of common UI components implemented with Liquid Glass, covering real-world use cases from popular applications. Each component includes SwiftUI and UIKit implementations.

## Table of Contents

- [Bottom Sheets](#bottom-sheets)
- [Action Sheets](#action-sheets)
- [Cards and Panels](#cards-and-panels)
- [Search Interfaces](#search-interfaces)
- [Media Players](#media-players)
- [Notification Banners](#notification-banners)
- [Popovers and Tooltips](#popovers-and-tooltips)
- [Login and Forms](#login-and-forms)
- [Onboarding](#onboarding)
- [Context Menus](#context-menus)

---

## Bottom Sheets

### Maps-Style Bottom Sheet (SwiftUI)

Expandable bottom sheet similar to Apple Maps.

```swift
struct MapsBottomSheet: View {
    @State private var detentHeight: PresentationDetent = .medium
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Park")
                        .font(.title2.bold())
                    Text("1 Apple Park Way")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: { }) {
                    Image(systemName: "bookmark")
                        .font(.title3)
                }
                .glassEffect(in: .circle)
            }
            .padding()

            Divider()

            // Quick actions
            HStack(spacing: 16) {
                QuickActionButton(icon: "car.fill", title: "Directions")
                QuickActionButton(icon: "phone.fill", title: "Call")
                QuickActionButton(icon: "square.and.arrow.up", title: "Share")
            }
            .padding()

            if isExpanded {
                // Extended content
                ScrollView {
                    Text("Additional details...")
                        .padding()
                }
            }
        }
        .glassEffect(.regular.tint(.white.opacity(0.1)))
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive())
    }
}
```

---

### Draggable Bottom Sheet (UIKit)

```swift
class DraggableBottomSheet: UIViewController {
    private let glassView = UIVisualEffectView()
    private let handleView = UIView()
    private var panGesture: UIPanGestureRecognizer!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGlass()
        setupGesture()
    }

    private func setupGlass() {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = .systemBackground.withAlphaComponent(0.1)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 20
        glassView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(glassView)

        // Handle indicator
        handleView.backgroundColor = .secondaryLabel.withAlphaComponent(0.5)
        handleView.layer.cornerRadius = 2.5
        handleView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(handleView)

        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            glassView.heightAnchor.constraint(equalToConstant: 400),

            handleView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 8),
            handleView.centerXAnchor.constraint(equalTo: glassView.contentView.centerXAnchor),
            handleView.widthAnchor.constraint(equalToConstant: 36),
            handleView.heightAnchor.constraint(equalToConstant: 5)
        ])
    }

    private func setupGesture() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        // Implement drag logic
    }
}
```

---

## Action Sheets

### Glass Action Sheet (SwiftUI)

Modern action sheet with glass styling.

```swift
struct GlassActionSheet: View {
    @Binding var isPresented: Bool
    let actions: [ActionItem]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(actions) { action in
                ActionButton(action: action) {
                    action.handler()
                    isPresented = false
                }
            }

            // Cancel button
            Button("Cancel") {
                isPresented = false
            }
            .font(.headline)
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding()
            .glassEffect(.regular.interactive())
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

struct ActionItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String?
    let style: ActionStyle
    let handler: () -> Void

    enum ActionStyle {
        case `default`, destructive
    }
}

struct ActionButton: View {
    let action: ActionItem
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            HStack {
                if let icon = action.icon {
                    Image(systemName: icon)
                }
                Text(action.title)
                    .font(.body)
                Spacer()
            }
            .foregroundColor(action.style == .destructive ? .red : .primary)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .glassEffect(.regular.interactive())
    }
}

// Usage
struct ContentView: View {
    @State private var showActionSheet = false

    var body: some View {
        Button("Show Actions") {
            showActionSheet = true
        }
        .sheet(isPresented: $showActionSheet) {
            GlassActionSheet(isPresented: $showActionSheet, actions: [
                ActionItem(title: "Share", icon: "square.and.arrow.up", style: .default) {
                    print("Share")
                },
                ActionItem(title: "Delete", icon: "trash", style: .destructive) {
                    print("Delete")
                }
            ])
            .presentationDetents([.height(200)])
        }
    }
}
```

---

## Cards and Panels

### Weather Card (SwiftUI)

Weather widget-style card with glass effect.

```swift
struct WeatherCard: View {
    let location: String
    let temperature: Int
    let condition: String
    let high: Int
    let low: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Location
            Text(location)
                .font(.title3)
                .foregroundColor(.secondary)

            // Current temperature
            HStack(alignment: .top) {
                Text("\(temperature)°")
                    .font(.system(size: 64, weight: .thin))

                VStack(alignment: .leading, spacing: 4) {
                    Text(condition)
                        .font(.title3)
                    HStack(spacing: 8) {
                        Text("H:\(high)°")
                        Text("L:\(low)°")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                Spacer()
            }

            // Hourly forecast
            HourlyForecast()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(.white.opacity(0.15)))
    }
}

struct HourlyForecast: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(0..<12) { hour in
                    VStack(spacing: 8) {
                        Text("\(hour):00")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "cloud.sun.fill")
                            .font(.title3)
                        Text("72°")
                            .font(.body.weight(.medium))
                    }
                }
            }
        }
    }
}
```

---

### Photo Info Card (UIKit)

Information card for photo details.

```swift
class PhotoInfoCard: UIView {
    private let glassView = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = .systemBackground.withAlphaComponent(0.2)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 16
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Icon
        let iconView = UIImageView(image: UIImage(systemName: "camera.fill"))
        iconView.tintColor = .label
        iconView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(iconView)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "Photo Details"
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(titleLabel)

        // Info stack
        let infoStack = createInfoStack()
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(infoStack)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 20),
            iconView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),

            infoStack.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            infoStack.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 20),
            infoStack.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -20),
            infoStack.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -20)
        ])
    }

    private func createInfoStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8

        let items = [
            ("Date", "Dec 25, 2025"),
            ("Time", "2:30 PM"),
            ("Location", "San Francisco, CA"),
            ("Camera", "iPhone 16 Pro")
        ]

        for (label, value) in items {
            let row = createInfoRow(label: label, value: value)
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func createInfoRow(label: String, value: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .equalSpacing

        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 15)
        labelView.textColor = .secondaryLabel

        let valueView = UILabel()
        valueView.text = value
        valueView.font = .systemFont(ofSize: 15, weight: .medium)

        stack.addArrangedSubview(labelView)
        stack.addArrangedSubview(valueView)

        return stack
    }
}
```

---

## Search Interfaces

### Spotlight-Style Search (SwiftUI)

Full-screen search interface with glass background.

```swift
struct SpotlightSearch: View {
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    isSearchFocused = false
                }

            VStack(spacing: 20) {
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .glassEffect(.regular.tint(.white.opacity(0.2)))

                // Results
                if !searchText.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<5) { index in
                                SearchResultRow(
                                    icon: "doc.text.fill",
                                    title: "Document \(index + 1)",
                                    subtitle: "Last modified today"
                                )
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}

struct SearchResultRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .glassEffect(.regular.interactive())
    }
}
```

---

## Media Players

### Mini Player Bar (SwiftUI)

Compact media player with glass styling.

```swift
struct MiniPlayerBar: View {
    @State private var isPlaying = false
    let artwork: String
    let title: String
    let artist: String

    var body: some View {
        HStack(spacing: 16) {
            // Artwork
            Image(artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Controls
            HStack(spacing: 20) {
                Button(action: {}) {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                }

                Button(action: { isPlaying.toggle() }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .contentTransition(.symbolEffect(.replace))

                Button(action: {}) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
            }
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(.white.opacity(0.1)))
        .animation(.spring(response: 0.3), value: isPlaying)
    }
}

// Usage in app
struct ContentView: View {
    var body: some View {
        VStack {
            Spacer()
            MiniPlayerBar(
                artwork: "album-cover",
                title: "Song Title",
                artist: "Artist Name"
            )
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}
```

---

## Notification Banners

### Glass Notification Banner (SwiftUI)

Floating notification banner with auto-dismiss.

```swift
struct NotificationBanner: View {
    let icon: String
    let title: String
    let message: String
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassEffect(.regular.tint(.white.opacity(0.2)))
        .shadow(color: .black.opacity(0.1), radius: 10)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isPresented = false
                }
            }
        }
    }
}

// Usage
struct ContentView: View {
    @State private var showNotification = false

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            ScrollView {
                // ...
            }

            // Notification banner
            if showNotification {
                NotificationBanner(
                    icon: "checkmark.circle.fill",
                    title: "Success",
                    message: "Your changes have been saved",
                    isPresented: $showNotification
                )
                .padding(.top, 50)
            }
        }
    }
}
```

---

## Popovers and Tooltips

### Glass Tooltip (SwiftUI)

Contextual tooltip with glass styling.

```swift
struct GlassTooltip: View {
    let text: String
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.white.opacity(0.3)))

                // Arrow
                Triangle()
                    .fill(Color.clear)
                    .frame(width: 12, height: 6)
                    .glassEffect(.regular.tint(.white.opacity(0.3)))
            }
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// Usage
struct ButtonWithTooltip: View {
    @State private var showTooltip = false

    var body: some View {
        VStack {
            GlassTooltip(text: "Tap to continue", isVisible: $showTooltip)

            Button("Help") {
                withAnimation {
                    showTooltip.toggle()
                }
            }
            .glassEffect()
        }
    }
}
```

---

## Login and Forms

### Glass Login Form (SwiftUI)

Modern login interface with glass components.

```swift
struct GlassLoginView: View {
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .padding(.bottom, 40)

                // Email field
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.secondary)
                    TextField("Email", text: $email)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                }
                .padding()
                .glassEffect(.regular.tint(.white.opacity(0.2)))

                // Password field
                HStack {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                    SecureField("Password", text: $password)
                        .textFieldStyle(.plain)
                }
                .padding()
                .glassEffect(.regular.tint(.white.opacity(0.2)))

                // Login button
                Button(action: login) {
                    Text("Log In")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .glassEffect(.regular.tint(.white.opacity(0.4)).interactive())

                // Forgot password
                Button("Forgot Password?") {
                    print("Forgot password")
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            }
            .padding(32)
        }
    }

    private func login() {
        print("Login with:", email)
    }
}
```

---

## Onboarding

### Glass Onboarding Card (SwiftUI)

Onboarding screen with glass cards.

```swift
struct OnboardingView: View {
    @State private var currentPage = 0
    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "star.fill",
            title: "Welcome",
            description: "Discover amazing features"
        ),
        OnboardingPage(
            icon: "bolt.fill",
            title: "Fast",
            description: "Lightning-fast performance"
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "Secure",
            description: "Your data is protected"
        )
    ]

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingCard(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Continue button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                }) {
                    Text(currentPage == pages.count - 1 ? "Get Started" : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .glassEffect(.regular.tint(.white.opacity(0.3)).interactive())
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

struct OnboardingCard: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundColor(.white)

            Text(page.title)
                .font(.largeTitle.bold())
                .foregroundColor(.white)

            Text(page.description)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .glassEffect(.regular.tint(.white.opacity(0.15)))
        .padding(.horizontal, 32)
    }
}
```

---

## Context Menus

### Glass Context Menu (UIKit)

Custom context menu with glass styling.

```swift
class GlassContextMenu: UIView {
    private let glassView = UIVisualEffectView()
    var onDismiss: (() -> Void)?

    init(items: [ContextMenuItem]) {
        super.init(frame: .zero)
        setupView(items: items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(items: [ContextMenuItem]) {
        // Glass background
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = .systemBackground.withAlphaComponent(0.2)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 12
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Stack view for items
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(stackView)

        // Add menu items
        for (index, item) in items.enumerated() {
            let button = createMenuButton(item: item)
            stackView.addArrangedSubview(button)

            if index < items.count - 1 {
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                stackView.addArrangedSubview(divider)
            }
        }

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),

            widthAnchor.constraint(equalToConstant: 200)
        ])
    }

    private func createMenuButton(item: ContextMenuItem) -> UIButton {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading

        var config = UIButton.Configuration.plain()
        config.title = item.title
        config.image = UIImage(systemName: item.icon)
        config.imagePlacement = .leading
        config.imagePadding = 12
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 12, leading: 16, bottom: 12, trailing: 16
        )

        if item.isDestructive {
            config.baseForegroundColor = .systemRed
        }

        button.configuration = config
        button.addAction(UIAction { [weak self] _ in
            item.action()
            self?.onDismiss?()
        }, for: .touchUpInside)

        return button
    }
}

struct ContextMenuItem {
    let title: String
    let icon: String
    let isDestructive: Bool
    let action: () -> Void
}

// Usage
let menu = GlassContextMenu(items: [
    ContextMenuItem(title: "Share", icon: "square.and.arrow.up", isDestructive: false) {
        print("Share")
    },
    ContextMenuItem(title: "Delete", icon: "trash", isDestructive: true) {
        print("Delete")
    }
])
```

---

## Platform-Specific Adaptations

### iPad Sidebar (SwiftUI)

Glass sidebar for iPad apps.

```swift
struct IPadSidebarView: View {
    @Binding var selectedItem: String?

    var body: some View {
        List(selection: $selectedItem) {
            Section("Favorites") {
                SidebarItem(icon: "star.fill", title: "Starred")
                SidebarItem(icon: "clock.fill", title: "Recent")
            }

            Section("Folders") {
                SidebarItem(icon: "folder.fill", title: "Documents")
                SidebarItem(icon: "folder.fill", title: "Downloads")
            }
        }
        .listStyle(.sidebar)
        // Glass styling automatic in iOS 26
    }
}

struct SidebarItem: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
    }
}
```

---

## Sources

- [Apple Developer Documentation - Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)
- [GitHub - LiquidGlassSwiftUI Sample](https://github.com/mertozseven/LiquidGlassSwiftUI)
- [Fatbobman - Grow on iOS 26](https://fatbobman.com/en/posts/grow-on-ios26)
- [Create with Swift - Exploring Liquid Glass](https://www.createwithswift.com/exploring-a-new-visual-language-liquid-glass/)
- [Appcircle Blog - Build a UIKit App with Liquid Glass Design](https://appcircle.io/blog/wwdc25-build-a-uikit-app-with-the-new-liquid-glass-design)
