import SwiftUI

public struct UserBubble: View {
  public var text: String
  @Environment(\.colorScheme) private var colorScheme

  public init(text: String) {
    self.text = text
  }

  public var body: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.secondary.opacity(colorScheme == .dark ? 0.24 : 0.12))
      }
  }
}
