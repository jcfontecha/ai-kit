import SwiftUI

struct ConversationDemoView: View {
  @State private var items: [String] = (1...30).map { "Message \($0)" }
  @State private var isAtBottom: Bool = false

  var body: some View {
    ZStack(alignment: .bottom) {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { index in
              HStack {
                if index.isMultiple(of: 2) {
                  Text(items[index])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
                  Spacer(minLength: 24)
                } else {
                  Spacer(minLength: 24)
                  Text(items[index])
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                      RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.03))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    )
                }
              }
              .id(index)
            }

            GeometryReader { geo in
              Color.clear
                .preference(key: BottomOffsetKey.self, value: geo.frame(in: .named("scroll")).maxY)
            }
            .frame(height: 1)
            .id("bottom")
          }
          .padding(12)
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(BottomOffsetKey.self) { bottomMaxY in
          // Approximate: when bottom is within the visible height, consider "at bottom".
          // (Good enough for the gallery; the production component can implement a more robust strategy.)
          let windowHeight: CGFloat = 520
          isAtBottom = bottomMaxY <= windowHeight + 40
        }
        .overlay(alignment: .topTrailing) {
          Button("Add") {
            items.append("Message \(items.count + 1)")
            proxy.scrollTo("bottom", anchor: .bottom)
          }
          .buttonStyle(.bordered)
          .padding(8)
        }

        if isAtBottom == false {
          Button {
            proxy.scrollTo("bottom", anchor: .bottom)
          } label: {
            Image(systemName: "arrow.down")
              .font(.headline)
              .frame(width: 44, height: 44)
          }
          .buttonStyle(.plain)
          .glassSurface(cornerRadius: 22, interactive: true)
          .padding(.bottom, 8)
        }
      }
    }
    .frame(height: 520)
  }
}

private struct BottomOffsetKey: PreferenceKey {
  static var defaultValue: CGFloat = .infinity
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
