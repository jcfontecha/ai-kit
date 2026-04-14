import SwiftUI

public struct UserBubble: View {
  public var text: String
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.chatTheme) private var chatTheme

  public init(text: String) {
    self.text = text
  }

  private var bubbleBackground: Color {
    if let themed = chatTheme.message.userBubble?.background { return themed }
    return Color.secondary.opacity(colorScheme == .dark ? 0.24 : 0.12)
  }

  public var body: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(bubbleBackground)
      }
  }
}
