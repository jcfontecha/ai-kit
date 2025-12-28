import SwiftUI

public struct ReasoningDisclosure<Content: View>: View {
  public var isStreaming: Bool
  @ViewBuilder public var content: () -> Content

  public init(isStreaming: Bool, @ViewBuilder content: @escaping () -> Content) {
    self.isStreaming = isStreaming
    self.content = content
  }

  public var body: some View {
    DisclosureGroup {
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    } label: {
      Text(isStreaming ? "Reasoning (streaming)" : "Reasoning")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color.primary.opacity(0.03))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }
  }
}

