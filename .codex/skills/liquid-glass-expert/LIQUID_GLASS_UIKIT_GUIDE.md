# Liquid Glass UIKit Implementation Guide

## Introduction

This comprehensive guide provides practical UIKit implementations of Liquid Glass components for iOS 26+. Each example includes production-ready code with Objective-C and Swift variants where applicable.

## Table of Contents

- [Basic Setup](#basic-setup)
- [Glass Effect Views](#glass-effect-views)
- [Navigation Components](#navigation-components)
- [Tab Bar Implementation](#tab-bar-implementation)
- [Interactive Controls](#interactive-controls)
- [Container Effects](#container-effects)
- [Toolbar Customization](#toolbar-customization)
- [Complete Examples](#complete-examples)
- [SwiftUI Integration](#swiftui-integration)

---

## Basic Setup

### Creating a Glass Effect View

The most basic implementation using `UIGlassEffect`:

```swift
import UIKit

class BasicGlassViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupGlassView()
    }

    private func setupGlassView() {
        // Create glass effect
        let glassEffect = UIGlassEffect(style: .regular)
        let glassView = UIVisualEffectView(effect: glassEffect)

        // Configure frame and corner radius
        glassView.frame = CGRect(x: 50, y: 100, width: 300, height: 200)
        glassView.layer.cornerRadius = 16
        glassView.layer.masksToBounds = true

        // Add to view hierarchy
        view.addSubview(glassView)

        // Add content to glass view
        let label = UILabel()
        label.text = "Glass Content"
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.textAlignment = .center
        label.frame = glassView.bounds
        glassView.contentView.addSubview(label)
    }
}
```

**Objective-C:**
```objc
- (void)setupGlassView {
    UIGlassEffect *glassEffect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:glassEffect];

    glassView.frame = CGRectMake(50, 100, 300, 200);
    glassView.layer.cornerRadius = 16;
    glassView.layer.masksToBounds = YES;

    [self.view addSubview:glassView];

    UILabel *label = [[UILabel alloc] init];
    label.text = @"Glass Content";
    label.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    label.textAlignment = NSTextAlignmentCenter;
    label.frame = glassView.bounds;
    [glassView.contentView addSubview:label];
}
```

---

### Glass Effect with Auto Layout

Using Auto Layout constraints for responsive glass views:

```swift
class GlassCardView: UIView {
    private let glassView = UIVisualEffectView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Configure glass effect
        glassView.effect = UIGlassEffect(style: .regular)
        glassView.layer.cornerRadius = 16
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Configure title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(titleLabel)

        // Configure subtitle
        subtitleLabel.font = .systemFont(ofSize: 16)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(subtitleLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -20)
        ])
    }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
}

// Usage
let card = GlassCardView()
card.configure(title: "Glass Card", subtitle: "With auto layout")
view.addSubview(card)
```

---

## Glass Effect Views

### Tinted Glass View

Glass with color tint:

```swift
class TintedGlassView: UIView {
    private let glassView = UIVisualEffectView()

    init(tintColor: UIColor, frame: CGRect = .zero) {
        super.init(frame: frame)
        setupGlass(tintColor: tintColor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupGlass(tintColor: UIColor) {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = tintColor
        glassView.effect = glassEffect

        glassView.layer.cornerRadius = 12
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(glassView)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    var contentView: UIView {
        glassView.contentView
    }
}

// Usage
let tintedGlass = TintedGlassView(
    tintColor: .systemBlue.withAlphaComponent(0.3)
)
```

---

### Interactive Glass Button

Button with interactive glass effect:

```swift
class GlassButton: UIButton {
    private let glassView = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGlass()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGlass()
    }

    private func setupGlass() {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        glassView.effect = glassEffect

        glassView.isUserInteractionEnabled = false
        glassView.layer.cornerRadius = bounds.height / 2
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false

        insertSubview(glassView, at: 0)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // Configure button appearance
        setTitleColor(.label, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glassView.layer.cornerRadius = bounds.height / 2
    }
}

// Usage
let button = GlassButton()
button.setTitle("Interactive Button", for: .normal)
button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
```

---

## Navigation Components

### Glass Navigation Bar

Custom navigation bar with glass background:

```swift
class GlassNavigationBar: UIView {
    private let glassView = UIVisualEffectView()
    private let titleLabel = UILabel()
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var leftButtonAction: (() -> Void)?
    var rightButtonAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Glass background
        let glassEffect = UIGlassEffect(style: .regular)
        glassView.effect = glassEffect
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Title
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(titleLabel)

        // Left button
        leftButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        leftButton.addTarget(self, action: #selector(leftButtonTapped), for: .touchUpInside)
        leftButton.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(leftButton)

        // Right button
        rightButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        rightButton.addTarget(self, action: #selector(rightButtonTapped), for: .touchUpInside)
        rightButton.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(rightButton)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            leftButton.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
            leftButton.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: 44),
            leftButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: glassView.contentView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),

            rightButton.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -16),
            rightButton.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: 44),
            rightButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func leftButtonTapped() {
        leftButtonAction?()
    }

    @objc private func rightButtonTapped() {
        rightButtonAction?()
    }
}

// Usage
let navBar = GlassNavigationBar()
navBar.title = "Messages"
navBar.leftButtonAction = { [weak self] in
    self?.navigationController?.popViewController(animated: true)
}
navBar.rightButtonAction = {
    print("Menu tapped")
}
```

---

### Standard Navigation Bar with Glass

Configuring UINavigationBar for glass appearance:

```swift
class GlassNavigationController: UINavigationController {
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
    }

    private func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()

        // Glass effect is automatic in iOS 26 when using transparent background
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}
```

---

## Tab Bar Implementation

### Custom Glass Tab Bar

Building a custom tab bar with glass effect:

```swift
class GlassTabBar: UIView {
    private let glassView = UIVisualEffectView()
    private var tabButtons: [UIButton] = []

    var selectedIndex: Int = 0 {
        didSet {
            updateSelection()
        }
    }

    var onTabSelected: ((Int) -> Void)?

    init(items: [TabItem]) {
        super.init(frame: .zero)
        setupView(items: items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(items: [TabItem]) {
        // Glass background
        let glassEffect = UIGlassEffect(style: .regular)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 24
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Stack view for tabs
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(stackView)

        // Create tab buttons
        for (index, item) in items.enumerated() {
            let button = createTabButton(item: item, index: index)
            tabButtons.append(button)
            stackView.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 8),
            stackView.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -8),
            stackView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -8)
        ])

        updateSelection()
    }

    private func createTabButton(item: TabItem, index: Int) -> UIButton {
        let button = UIButton(type: .system)

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        let image = UIImage(systemName: item.iconName, withConfiguration: config)
        button.setImage(image, for: .normal)
        button.setTitle(item.title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 10, weight: .medium)

        button.tag = index
        button.addTarget(self, action: #selector(tabButtonTapped(_:)), for: .touchUpInside)

        // Layout
        button.imageView?.contentMode = .scaleAspectFit
        button.titleLabel?.textAlignment = .center

        // Vertical layout
        button.imageEdgeInsets = UIEdgeInsets(top: -8, left: 0, bottom: 8, right: 0)
        button.titleEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: -8, right: 0)

        return button
    }

    @objc private func tabButtonTapped(_ sender: UIButton) {
        selectedIndex = sender.tag
        onTabSelected?(sender.tag)
    }

    private func updateSelection() {
        for (index, button) in tabButtons.enumerated() {
            button.tintColor = index == selectedIndex ? .systemBlue : .secondaryLabel
        }
    }
}

struct TabItem {
    let iconName: String
    let title: String
}

// Usage
let tabBar = GlassTabBar(items: [
    TabItem(iconName: "house.fill", title: "Home"),
    TabItem(iconName: "magnifyingglass", title: "Search"),
    TabItem(iconName: "bell.fill", title: "Alerts"),
    TabItem(iconName: "person.fill", title: "Profile")
])

tabBar.onTabSelected = { index in
    print("Selected tab:", index)
}
```

---

### UITabBarController with Glass

Configuring standard UITabBarController:

```swift
class GlassTabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabBar()
        setupViewControllers()
    }

    private func configureTabBar() {
        // Enable minimize behavior
        tabBarMinimizeBehavior = .onScrollDown

        // Glass appearance is automatic in iOS 26
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func setupViewControllers() {
        let homeVC = HomeViewController()
        homeVC.tabBarItem = UITabBarItem(
            title: "Home",
            image: UIImage(systemName: "house"),
            selectedImage: UIImage(systemName: "house.fill")
        )

        let searchVC = SearchViewController()
        searchVC.tabBarItem = UITabBarItem(
            title: "Search",
            image: UIImage(systemName: "magnifyingglass"),
            tag: 1
        )

        viewControllers = [homeVC, searchVC]
    }
}
```

---

## Interactive Controls

### Glass Toggle Switch

Custom toggle with glass background:

```swift
class GlassToggleView: UIView {
    private let glassView = UIVisualEffectView()
    private let titleLabel = UILabel()
    private let toggle = UISwitch()

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var isOn: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }

    var onToggleChanged: ((Bool) -> Void)?

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
        glassEffect.isInteractive = true
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 12
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(titleLabel)

        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 16),

            glassView.contentView.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    @objc private func toggleChanged() {
        onToggleChanged?(toggle.isOn)
    }
}
```

---

## Container Effects

### Glass Container for Multiple Views

Using `UIGlassContainerEffect` to group glass elements:

```swift
class GlassToolbar: UIView {
    private let containerView = UIVisualEffectView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupContainer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContainer()
    }

    private func setupContainer() {
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = 20
        containerView.effect = containerEffect
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // Create individual glass buttons
        let button1 = createGlassButton(icon: "square.and.arrow.up")
        let button2 = createGlassButton(icon: "heart")
        let button3 = createGlassButton(icon: "bookmark")

        containerView.contentView.addSubview(button1)
        containerView.contentView.addSubview(button2)
        containerView.contentView.addSubview(button3)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            button1.leadingAnchor.constraint(equalTo: containerView.contentView.leadingAnchor, constant: 16),
            button1.centerYAnchor.constraint(equalTo: containerView.contentView.centerYAnchor),

            button2.centerXAnchor.constraint(equalTo: containerView.contentView.centerXAnchor),
            button2.centerYAnchor.constraint(equalTo: containerView.contentView.centerYAnchor),

            button3.trailingAnchor.constraint(equalTo: containerView.contentView.trailingAnchor, constant: -16),
            button3.centerYAnchor.constraint(equalTo: containerView.contentView.centerYAnchor)
        ])
    }

    private func createGlassButton(icon: String) -> UIView {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.isInteractive = true
        let glassView = UIVisualEffectView(effect: glassEffect)

        glassView.layer.cornerRadius = 22
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: UIImage(systemName: icon))
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(imageView)

        NSLayoutConstraint.activate([
            glassView.widthAnchor.constraint(equalToConstant: 44),
            glassView.heightAnchor.constraint(equalToConstant: 44),
            imageView.centerXAnchor.constraint(equalTo: glassView.contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 22),
            imageView.heightAnchor.constraint(equalToConstant: 22)
        ])

        return glassView
    }
}
```

---

## Toolbar Customization

### Navigation Bar with Badges

Using the new badge API on bar button items:

```swift
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
    }

    private func setupNavigationBar() {
        title = "Messages"

        // Folder button with badge
        let folderButton = UIBarButtonItem(
            image: UIImage(systemName: "folder"),
            style: .plain,
            target: self,
            action: #selector(folderTapped)
        )
        folderButton.badge = .count(5)

        // Flag button with prominent style
        let flagButton = UIBarButtonItem(
            image: UIImage(systemName: "flag.fill"),
            style: .plain,
            target: self,
            action: #selector(flagTapped)
        )
        flagButton.tintColor = .systemOrange

        // Share button
        let shareButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(shareTapped)
        )

        // Add fixed space
        navigationItem.rightBarButtonItems = [
            shareButton,
            .fixedSpace(0),
            flagButton,
            folderButton
        ]
    }

    @objc private func folderTapped() {
        // Remove badge after tapping
        navigationItem.rightBarButtonItems?.last?.badge = nil
    }

    @objc private func flagTapped() { }
    @objc private func shareTapped() { }
}
```

---

### Toolbar with Glass Blur

Custom toolbar with flexible spacing:

```swift
class GlassToolbarViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
    }

    private func setupToolbar() {
        let flexibleSpace = UIBarButtonItem.flexibleSpace()
        flexibleSpace.hidesSharedBackground = false

        let locationButton = UIBarButtonItem(
            image: UIImage(systemName: "location"),
            style: .plain,
            target: self,
            action: #selector(locationTapped)
        )

        let cameraButton = UIBarButtonItem(
            image: UIImage(systemName: "camera"),
            style: .plain,
            target: self,
            action: #selector(cameraTapped)
        )

        toolbarItems = [
            locationButton,
            flexibleSpace,
            cameraButton
        ]

        navigationController?.isToolbarHidden = false
    }

    @objc private func locationTapped() { }
    @objc private func cameraTapped() { }
}
```

---

## Complete Examples

### Glass Chat Input View

Production-ready chat input with multiline support:

```swift
class GlassChatInputView: UIView {
    private let glassView = UIVisualEffectView()
    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let placeholderLabel = UILabel()

    var onSendMessage: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Glass background
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = .systemBackground.withAlphaComponent(0.1)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 20
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glassView)

        // Text view
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(textView)

        // Placeholder
        placeholderLabel.text = "Message"
        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .secondaryLabel
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)

        // Send button
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let image = UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        sendButton.setImage(image, for: .normal)
        sendButton.tintColor = .systemBlue
        sendButton.addTarget(self, action: #selector(sendButtonTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(sendButton)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: topAnchor),
            glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
            glassView.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: glassView.contentView.topAnchor, constant: 4),
            textView.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            textView.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -4),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
            textView.heightAnchor.constraint(lessThanOrEqualToConstant: 120),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17),

            sendButton.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32)
        ])

        updateSendButton()
    }

    @objc private func sendButtonTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        onSendMessage?(text)
        textView.text = ""
        placeholderLabel.isHidden = false
        updateSendButton()
    }

    private func updateSendButton() {
        let isEmpty = textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = !isEmpty
        sendButton.tintColor = isEmpty ? .secondaryLabel : .systemBlue
    }
}

extension GlassChatInputView: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButton()
    }
}

// Usage
let chatInput = GlassChatInputView()
chatInput.onSendMessage = { message in
    print("Send:", message)
}
```

---

### Glass Settings Screen

Complete settings view controller:

```swift
class GlassSettingsViewController: UITableViewController {
    private let settings = [
        Setting(title: "Notifications", isToggle: true, value: true),
        Setting(title: "Dark Mode", isToggle: true, value: false),
        Setting(title: "Language", isToggle: false, value: nil)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.register(GlassSettingCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        settings.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! GlassSettingCell
        cell.configure(with: settings[indexPath.row])
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        64
    }
}

struct Setting {
    let title: String
    let isToggle: Bool
    let value: Bool?
}

class GlassSettingCell: UITableViewCell {
    private let glassView = UIVisualEffectView()
    private let titleLabel = UILabel()
    private let toggle = UISwitch()
    private let chevron = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        backgroundColor = .clear
        selectionStyle = .none

        let glassEffect = UIGlassEffect(style: .regular)
        glassView.effect = glassEffect
        glassView.layer.cornerRadius = 12
        glassView.layer.masksToBounds = true
        glassView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(glassView)

        titleLabel.font = .systemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(titleLabel)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(toggle)

        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = .secondaryLabel
        chevron.translatesAutoresizingMaskIntoConstraints = false
        glassView.contentView.addSubview(chevron)

        NSLayoutConstraint.activate([
            glassView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            glassView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            glassView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            glassView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            titleLabel.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: glassView.contentView.centerYAnchor)
        ])
    }

    func configure(with setting: Setting) {
        titleLabel.text = setting.title

        if setting.isToggle {
            toggle.isHidden = false
            chevron.isHidden = true
            toggle.isOn = setting.value ?? false
        } else {
            toggle.isHidden = true
            chevron.isHidden = false
        }
    }
}
```

---

## SwiftUI Integration

### Hosting SwiftUI Glass Views in UIKit

Using `UIHostingController` to embed SwiftUI glass components:

```swift
import SwiftUI

class UIKitViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        embedSwiftUIGlassView()
    }

    private func embedSwiftUIGlassView() {
        let swiftUIView = SwiftUIGlassButton()
        let hostingController = UIHostingController(rootView: swiftUIView)

        // Configure sizing
        hostingController.sizingOptions = [.intrinsicContentSize]

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        // Layout
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

struct SwiftUIGlassButton: View {
    var body: some View {
        Button("SwiftUI Glass Button") {
            print("Tapped")
        }
        .padding()
        .glassEffect()
    }
}
```

---

## Accessibility

### Reduce Transparency Support

```swift
class AccessibleGlassView: UIView {
    private var glassView: UIVisualEffectView?
    private var fallbackView: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        if UIAccessibility.isReduceTransparencyEnabled {
            showFallback()
        } else {
            showGlass()
        }
    }

    @objc private func accessibilityChanged() {
        setupView()
    }

    private func showGlass() {
        fallbackView?.removeFromSuperview()
        fallbackView = nil

        let glassEffect = UIGlassEffect(style: .regular)
        let glass = UIVisualEffectView(effect: glassEffect)
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        glassView = glass
    }

    private func showFallback() {
        glassView?.removeFromSuperview()
        glassView = nil

        let fallback = UIView()
        fallback.backgroundColor = .systemBackground.withAlphaComponent(0.95)
        fallback.layer.cornerRadius = 12
        fallback.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fallback)

        NSLayoutConstraint.activate([
            fallback.topAnchor.constraint(equalTo: topAnchor),
            fallback.leadingAnchor.constraint(equalTo: leadingAnchor),
            fallback.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallback.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        fallbackView = fallback
    }

    var contentView: UIView {
        glassView?.contentView ?? fallbackView ?? self
    }
}
```

---

## Sources

- [Appcircle Blog - Build a UIKit App with Liquid Glass Design](https://appcircle.io/blog/wwdc25-build-a-uikit-app-with-the-new-liquid-glass-design)
- [Fatbobman - Grow on iOS 26 - Liquid Glass Adaptation](https://fatbobman.com/en/posts/grow-on-ios26)
- [Apple Developer Documentation - Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [WWDC25 Session - What's New in UIKit](https://developer.apple.com/videos/play/wwdc2025/)
