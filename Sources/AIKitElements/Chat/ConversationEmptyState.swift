import SwiftUI

public struct ConversationEmptyState<Icon: View>: View {
  public var title: String
  public var description: String?
  public var icon: Icon

  @Environment(\.chatTheme) private var chatTheme

  public init(
    title: String,
    description: String? = nil,
    icon: Icon
  ) {
    self.title = title
    self.description = description
    self.icon = icon
  }

  public init(
    title: String,
    description: String? = nil
  ) where Icon == EmptyView {
    self.title = title
    self.description = description
    self.icon = EmptyView()
  }

  public var body: some View {
    VStack(spacing: 12) {
      icon
        .foregroundStyle(.secondary)

      Text(title)
        .font(.headline)

      if let description {
        Text(description)
          .font(.subheadline)
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
      }
    }
    .padding(chatTheme.spacing.contentPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

