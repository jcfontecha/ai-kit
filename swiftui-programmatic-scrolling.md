Below is a clean **Markdown extraction** of the article content (text, structure, and code), with navigation, ads, and unrelated Medium UI elements removed.

---

# Scroll Programmatically With SwiftUI ScrollView

*By Sasha Myshkina*
*4 min read · Aug 14, 2023*

When looking into ways to implement UIKit’s `setContentOffset(_:animated:)` in SwiftUI, you may run into many approaches. Some — such as using the `id` for `ScrollView` and redrawing the whole thing — are fairly creative, though rather excessive in 2023.

This article presents **simpler, modern ways** to set a SwiftUI `ScrollView` offset programmatically.

---

## Modern Approach for iOS 17.0+

In iOS 17, Apple introduced the modifier:

```swift
scrollPosition(id:anchor:)
```

It works beautifully with `LazyVStack` and `LazyHStack`, allowing you to scroll not only to the top or bottom but to **any view inside a `ScrollView`**.

As the official documentation highlights:

> Use the `scrollTargetLayout()` modifier to configure the layout that contains your scroll targets.

---

## Example Goal

Implement:

* Scroll to the **top**
* Scroll to the **bottom**
* Scroll to a **specific view**

---

## View Model

```swift
import SwiftUI

final class ScrollViewContentModel: ObservableObject {

    // MARK: - Properties
    var contentItems: [ContentItem] = ContentItem.defaultContent()
}

struct ContentItem: Identifiable {

    // MARK: - Properties
    var id: Int
    var colour: Color

    // MARK: - Init
    init(id: Int, colour: Color?) {
        self.id = id
        self.colour = colour ?? .gray
    }

    static func defaultContent() -> [ContentItem] {
        let colours: [Color] = .randomColours()
        return colours.enumerated().map { iterator, colour in
            ContentItem(id: iterator, colour: colour)
        }
    }
}
```

Each item contains only an `id` and a `Color` for demonstration purposes.

---

## Content View with `scrollPosition`

```swift
struct ContentView: View {

    // MARK: - Properties
    @StateObject var viewModel = ScrollViewContentModel()

    // Initial scroll offset aligned with the first view
    @State private var scrollPosition: Int? = 0

    // MARK: - Body
    var body: some View {
        VStack(spacing: Constant.vstackSpacing) {

            buttonView

            ScrollView(.vertical) {
                LazyVStack {
                    ForEach(viewModel.contentItems) { item in
                        rectangleView(
                            colour: item.colour,
                            text: "\(item.id)"
                        )
                        .containerRelativeFrame([.vertical, .horizontal])
                    }
                }
                // Declare LazyVStack as scroll target layout
                .scrollTargetLayout()
            }
            // Bind scroll offset to a specific view id
            .scrollPosition(id: $scrollPosition)
            .safeAreaPadding(.horizontal, Constant.safeAreaPadding)
        }
        .safeAreaPadding(.bottom, Constant.safeAreaPadding)
    }
}
```

---

## Buttons to Control Scroll Position

### Scroll to Top

```swift
private var buttonTop: some View {
    Button(action: {
        scrollPosition = 0
    }) {
        Image(systemName: "arrow.up")
            .foregroundColor(.white)
    }
    .padding(.horizontal, Constant.safeAreaPadding)
}
```

---

### Scroll to Bottom

```swift
private var buttonBottom: some View {
    Button(action: {
        scrollPosition = viewModel.contentItems.count - 1
    }) {
        Image(systemName: "arrow.down")
            .foregroundColor(.white)
    }
    .padding(.horizontal, Constant.safeAreaPadding)
}
```

---

### Scroll to Next View

```swift
private var nextViewButton: some View {
    Button("Next page") {
        scrollPosition = scrollPosition == nil ? 0 : (scrollPosition! + 1)
    }
}
```

---

### Button Container View

```swift
private var buttonView: some View {
    ZStack {
        Color.black

        HStack {
            buttonTop

            VStack {
                nextViewButton
                    .padding(5)

                if let position = scrollPosition {
                    Text("Current page: \(position)")
                        .foregroundColor(.white)
                }
            }

            buttonBottom
        }
    }
    .frame(height: Constant.buttonViewHeight)
}
```

---

## Result

The buttons dynamically update the scroll position:

* Top button scrolls to the first view
* Bottom button scrolls to the last view
* “Next page” scrolls sequentially through items

**Source code:**
[https://github.com/sashamyshkina/scroll-swiftui/blob/main/swiftUI_scrollView/ContentView3.swift](https://github.com/sashamyshkina/scroll-swiftui/blob/main/swiftUI_scrollView/ContentView3.swift)

---

## ScrollViewReader (iOS 14.0+)

For iOS versions below 17, `ScrollViewReader` provides similar functionality using a proxy.

---

### Button View Using ScrollViewProxy

```swift
private func buttonView(with proxy: ScrollViewProxy) -> some View {
    ZStack {
        Color.black

        HStack {
            topButton(with: proxy)

            VStack {
                Button("Next page") {
                    if currentId < viewModel.contentItems.count - 1 {
                        proxy.scrollTo(currentId + 1)
                        currentId += 1
                    }
                }
                .padding(5)

                Text("Current page: \(currentId)")
                    .foregroundColor(.white)
            }

            bottomButton(with: proxy)
        }
    }
    .frame(height: Constant.buttonViewHeight)
}
```

---

### Top & Bottom Buttons

```swift
private func topButton(with proxy: ScrollViewProxy) -> some View {
    Button(action: {
        proxy.scrollTo(0)
        currentId = 0
    }) {
        Image(systemName: "arrow.up")
            .foregroundColor(.white)
    }
    .padding(.horizontal, Constant.safeAreaPadding)
}

private func bottomButton(with proxy: ScrollViewProxy) -> some View {
    Button(action: {
        let lastItemId = viewModel.contentItems.count - 1
        proxy.scrollTo(lastItemId)
        currentId = lastItemId
    }) {
        Image(systemName: "arrow.down")
            .foregroundColor(.white)
    }
    .padding(.horizontal, Constant.safeAreaPadding)
}
```

---

### Content View with IDs

```swift
@StateObject var viewModel = ScrollViewContentModel()
@State var currentId: Int = 0

var body: some View {
    VStack(spacing: Constant.vstackSpacing) {
        ScrollViewReader { proxy in

            buttonView(with: proxy)

            ScrollView(.vertical) {
                LazyVStack {
                    ForEach(viewModel.contentItems) { item in
                        rectangleView(
                            colour: item.colour,
                            text: "\(item.id)"
                        )
                        .containerRelativeFrame([.vertical, .horizontal])
                        .id(item.id) // Required for scrollTo
                    }
                }
            }
            .scrollDisabled(true)
            .safeAreaPadding(.horizontal, Constant.safeAreaPadding)
        }
    }
    .safeAreaPadding(.bottom, Constant.safeAreaPadding)
}
```

This achieves the same scrolling behavior as `scrollPosition(id:)`, using APIs available since iOS 14.

**Source code:**
[https://github.com/sashamyshkina/scroll-swiftui/blob/main/swiftUI_scrollView/ContentView3_iOS14.swift](https://github.com/sashamyshkina/scroll-swiftui/blob/main/swiftUI_scrollView/ContentView3_iOS14.swift)

---

## Conclusion

* **iOS 17+**: Prefer `scrollPosition(id:)` with `scrollTargetLayout()`
* **iOS 14–16**: Use `ScrollViewReader` with explicit child view IDs
* Both approaches allow precise, programmatic scrolling without hacks or view rebuilding

**Happy coding!**

--------------------------------

Here’s a clean **Markdown extraction** of the article **“Mastering ScrollView in SwiftUI. Scroll Offset”** with navigation, ads, and unrelated site content removed. The content is structured and ready to drop into notes or docs.

---

# Mastering ScrollView in SwiftUI: Scroll Offset

*By Majid Jabrayilov*
*June 17, 2024*

WWDC 2024 is over, and Apple continues filling long-standing gaps in SwiftUI. One of the most important improvements this year is **granular control over scroll position**. In this post, we’ll learn how to manipulate **and read** the scroll offset in SwiftUI.

---

## Scrolling by View Identifiers (Existing Approach)

SwiftUI already allows us to track and set scroll position using view identifiers. While this works, it’s not precise enough to fully understand or react to user interaction.

```swift
struct ContentView: View {
    @State private var position: Int?

    var body: some View {
        ScrollView {
            LazyVStack {
                ForEach(0..<100) { index in
                    Text(verbatim: index.formatted())
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $position)
    }
}
```

This approach is limited because it only operates on view IDs and does not expose offset-level information.

---

## Introducing `ScrollPosition`

SwiftUI introduces the new `ScrollPosition` type, which allows us to combine scrolling by:

* Edge (`.top`, `.bottom`)
* View identifier
* Offset (`CGPoint`)
* Axis (`x` or `y`)

---

## Scrolling to Top and Bottom Using Edges

```swift
struct ContentView: View {
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Button("Scroll to bottom") {
                position.scrollTo(edge: .bottom)
            }

            ForEach(1..<100) { index in
                Text(verbatim: index.formatted())
                    .id(index)
            }

            Button("Scroll to top") {
                position.scrollTo(edge: .top)
            }
        }
        .scrollPosition($position)
    }
}
```

Here, the scroll view is bound to a `ScrollPosition` state value, and buttons call `scrollTo` with specific edges.

---

## Animating Programmatic Scrolling

You can easily animate scrolling by attaching an animation modifier keyed off the `ScrollPosition` value.

```swift
.scrollPosition($position)
.animation(.default, value: position)
```

SwiftUI automatically animates whenever the position changes programmatically.

---

## Scrolling to a Specific View with an Anchor

```swift
struct ContentView: View {
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Button("Scroll somewhere") {
                let id = (1..<100).randomElement() ?? 0
                position.scrollTo(id: id, anchor: .center)
            }

            ForEach(1..<100) { index in
                Text(verbatim: index.formatted())
                    .id(index)
            }
        }
        .scrollPosition($position)
        .animation(.default, value: position)
    }
}
```

Using an anchor lets you decide which part of the target view (top, center, bottom) should be visible.

---

## Scrolling by Offset (CGPoint)

The `ScrollPosition` type also allows scrolling to an exact point.

```swift
struct ContentView: View {
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Button("Scroll to offset") {
                position.scrollTo(point: CGPoint(x: 0, y: 100))
            }

            ForEach(1..<100) { index in
                Text(verbatim: index.formatted())
                    .id(index)
            }
        }
        .scrollPosition($position)
        .animation(.default, value: position)
    }
}
```

---

## Scrolling Along a Single Axis

You can scroll independently along the X or Y axis.

```swift
struct ContentView: View {
    @State private var position = ScrollPosition(edge: .top)

    var body: some View {
        ScrollView {
            Button("Scroll to offset") {
                position.scrollTo(y: 100)
                position.scrollTo(x: 200)
            }

            ForEach(1..<100) { index in
                Text(verbatim: index.formatted())
                    .id(index)
            }
        }
        .scrollPosition($position)
        .animation(.default, value: position)
    }
}
```

---

## Reading Scroll Position State

The `ScrollPosition` type exposes optional properties:

* `edge`
* `point`
* `viewID`

These values are available **only when scrolling programmatically**.
When the user scrolls manually, these properties become `nil`.

To detect user interaction, use:

```swift
position.isPositionedByUser
```

This tells you whether the scroll position was moved by a gesture instead of code.

---

## Limitation: Reading User Scroll Offset

While `ScrollPosition` is excellent for **controlling** scrolling, it cannot read the exact offset when the user scrolls manually.

To solve this, SwiftUI provides:

```swift
.onScrollGeometryChange
```

This modifier enables offset tracking during user interaction and will be covered in a follow-up post.

---

## Summary

* `ScrollPosition` enables precise, flexible programmatic scrolling
* Supports scrolling by edge, ID, anchor, offset, and axis
* Automatically integrates with SwiftUI animations
* Can distinguish between user-driven and programmatic scrolling
* Does **not** expose live offset during user gestures (use `onScrollGeometryChange` for that)

---

*Thanks for reading. See you next week!*

--------------------------------

Here’s a **clean Markdown extraction** of the **Apple Developer Documentation page for `ScrollViewReader`**, with navigation chrome, symbol index noise, and unrelated sidebar content removed. This is distilled to the *actual documentation content* you’d want to keep in notes.

---

# ScrollViewReader

*A view that provides programmatic scrolling by working with a proxy to scroll to known child views.*

**Availability**

* iOS 14.0+
* iPadOS 14.0+
* macOS 11.0+
* Mac Catalyst 14.0+
* tvOS 14.0+
* watchOS 7.0+
* visionOS 1.0+

---

## Declaration

```swift
@frozen struct ScrollViewReader<Content> where Content : View
```

---

## Overview

`ScrollViewReader` enables programmatic scrolling inside a `ScrollView` by providing a **`ScrollViewProxy`** to its content.

The content view builder receives a `ScrollViewProxy` instance, which you use to scroll to child views using:

```swift
proxy.scrollTo(_:anchor:)
```

This allows scrolling to views that have a known identifier.

---

## Basic Example

The following example creates a scroll view with 100 items and two buttons. Each button scrolls to the opposite end of the list.

```swift
@Namespace var topID
@Namespace var bottomID

var body: some View {
    ScrollViewReader { proxy in
        ScrollView {
            Button("Scroll to Bottom") {
                withAnimation {
                    proxy.scrollTo(bottomID)
                }
            }
            .id(topID)

            VStack(spacing: 0) {
                ForEach(0..<100) { i in
                    color(fraction: Double(i) / 100)
                        .frame(height: 32)
                }
            }

            Button("Top") {
                withAnimation {
                    proxy.scrollTo(topID)
                }
            }
            .id(bottomID)
        }
    }
}

func color(fraction: Double) -> Color {
    Color(
        red: fraction,
        green: 1 - fraction,
        blue: 0.5
    )
}
```

---

## How It Works

* Each scroll target must have a **stable identifier** using `.id(...)`
* `ScrollViewReader` injects a `ScrollViewProxy`
* The proxy is used **inside actions**, not during view construction
* Scrolling can be animated using `withAnimation`

---

## Important Usage Rules

> **Do not use `ScrollViewProxy` during view construction.**

Using the proxy directly inside the content view builder will cause a **runtime error**.

✅ **Allowed**

* Button actions
* Gesture handlers
* `onChange(of:)`

❌ **Not allowed**

* Calling `proxy.scrollTo` directly while building the view hierarchy

---

## Key API

### Initializer

```swift
init(content: (ScrollViewProxy) -> Content)
```

Creates a scroll view reader that enables programmatic scrolling.

---

### Content Property

```swift
var content: (ScrollViewProxy) -> Content
```

The view builder that receives the `ScrollViewProxy`.

---

## Related Types

* `ScrollView`
* `ScrollViewProxy`

---

## When to Use ScrollViewReader

Use `ScrollViewReader` when:

* You need **programmatic scrolling** on iOS 14–16
* You want to scroll to **specific views by ID**
* You don’t need pixel-precise offset control

For **iOS 17+**, prefer `ScrollPosition` when you need:

* Offset-based scrolling
* Edge-based scrolling
* Distinguishing user vs programmatic scroll

---

## Summary

* `ScrollViewReader` enables programmatic scrolling via `ScrollViewProxy`
* Requires identifiable child views
* Works across all Apple platforms
* Best suited for ID-based scrolling
* Still relevant for backward compatibility


--------------------------------

All good 🙂 — here’s the **clean Markdown extraction** of the Stackademic article, with Medium UI, promos, and noise removed. This is the *core content only*, structured and ready for notes.

---

# SwiftUI: Mastering List

*(Programmatic Scroll, Set Initial Visible Item, Detect Reached Items)*

*By Itsuki*
*April 6, 2024 · 6 min read*

A `List` is a container that presents rows of data arranged in a single column, optionally supporting selection.

This article focuses on **Lists**, but the same ideas apply to `LazyVStack`.

---

## List vs LazyVStack

The author prefers `List` because it renders items in order.

Notes on behavior:

* **iOS < 15**: A full-screen `List` eagerly renders ~15–20 items, which can affect `onAppear`
* **iOS 15+**: `List` behaves lazily, similar to `LazyVStack`

---

## Topics Covered

* Programmatically scroll a `List`
* Set the initial visible item
* Detect when the first or last item is reached (e.g. for pagination)

---

## Setup

```swift
import SwiftUI

struct ListDemo: View {

    @State var list: [String] = (0...30).map { "Index\($0)" }

    var body: some View {
        List {
            ForEach(0..<list.count, id: \.self) { i in
                let item = list[i]
                Text(item)
                    .frame(height: 100, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden, edges: .all)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .listStyle(.plain)
    }
}

#Preview {
    ListDemo()
}
```

---

## Programmatically Scrolling a List

Wrap the `List` inside `ScrollViewReader`.

```swift
ScrollViewReader { proxy in
    List {
        // content
    }
}
```

The reader provides a `ScrollViewProxy`, which lets you scroll using:

```swift
proxy.scrollTo(_:anchor:)
```

---

## Assigning IDs

Each row must have a stable ID.

```swift
ForEach(0..<list.count, id: \.self) { i in
    Text(list[i])
        .id(i)
}
```

---

## Programmatic Scroll (No Animation)

```swift
ScrollViewReader { proxy in
    VStack {
        Button("Jump to top") {
            proxy.scrollTo(0, anchor: .top)
        }

        List {
            ForEach(0..<list.count, id: \.self) { i in
                Text(list[i])
                    .frame(height: 100)
                    .id(i)
            }
        }
        .listStyle(.plain)
    }
}
```

Supported anchors include `.top`, `.center`, and `.bottom`.

---

## Programmatic Scroll (With Animation)

Wrap the call in `withAnimation`.

```swift
Button("Jump to top") {
    withAnimation(.default) {
        proxy.scrollTo(0, anchor: .top)
    }
}
```

---

## Set the Initial Visible Item

Call `scrollTo` inside `onAppear`.

```swift
List {
    ForEach(0..<list.count, id: \.self) { i in
        Text(list[i])
            .frame(height: 100)
            .id(i)
    }
}
.onAppear {
    proxy.scrollTo(4, anchor: .top)
}
```

This makes item `id = 4` the first visible row.

---

## Detect When an Item Is Reached

Think of this as **detecting when an item appears**.

```swift
ForEach(0..<list.count, id: \.self) { i in
    Text(list[i])
        .id(i)
        .onAppear {
            if i == list.count - 1 {
                print("last visible row")
            } else if i == 0 {
                print("first visible row")
            }
        }
}
```

---

## Infinite Scrolling (Appending Items)

```swift
.onAppear {
    if i == list.count - 1 {
        Task {
            let newItems = (list.count...list.count+30)
                .map { "New Item: Index\($0)" }
            list.append(contentsOf: newItems)
        }
    }
}
```

---

## Prepending Items (Handling the Jump)

When prepending, IDs shift, causing the list to jump to the top.

Fix it by scrolling back to the original item.

```swift
Task {
    let newItems = (0...10).map { "Previous Item: Index\($0)" }
    list.insert(contentsOf: newItems, at: 0)
    proxy.scrollTo(10, anchor: .top)
}
```

Reducing the number of prepended items minimizes visible jumps.

---

## Full Example

```swift
import SwiftUI

struct ListDemo: View {

    @State var list: [String] = (0...30).map { "Index\($0)" }

    var body: some View {
        ScrollViewReader { proxy in
            VStack {
                Button("Jump to top") {
                    withAnimation(.default) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }

                List {
                    ForEach(0..<list.count, id: \.self) { i in
                        Text(list[i])
                            .frame(height: 100)
                            .id(i)
                            .onAppear {
                                if i == list.count - 1 {
                                    Task {
                                        let newItems =
                                            (list.count...list.count+30)
                                            .map { "New Item: Index\($0)" }
                                        list.append(contentsOf: newItems)
                                    }
                                } else if i == 0 {
                                    Task {
                                        let newItems =
                                            (0...10)
                                            .map { "Previous Item: Index\($0)" }
                                        list.insert(contentsOf: newItems, at: 0)
                                        proxy.scrollTo(10, anchor: .top)
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    proxy.scrollTo(1, anchor: .top)
                }
            }
        }
    }
}
```

---

## Key Takeaways

* `ScrollViewReader` enables programmatic scrolling for `List`
* Use `.id()` on rows for stable scroll targets
* `onAppear` is effective for detecting visible items
* Appending is easy; prepending requires scroll correction
* These patterns apply equally to `LazyVStack`