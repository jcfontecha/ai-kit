import SwiftUI

struct MessageDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      MessageBubble(role: .assistant, text: "Hello! I'm the assistant. This is a normal, readable bubble.")
      MessageBubble(role: .user, text: "And I'm the user. Bubbles should not be glass by default.")
      MessageBubble(role: .assistant, text: "Markdown/code should render on a non-glass surface for legibility.")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private enum DemoRole { case user, assistant }

private struct MessageBubble: View {
  let role: DemoRole
  let text: String

  var body: some View {
    HStack {
      if role == .assistant {
        bubble
        Spacer(minLength: 24)
      } else {
        Spacer(minLength: 24)
        bubble
      }
    }
  }

  private var bubble: some View {
    Text(text)
      .font(.body)
      .foregroundStyle(.primary)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(role == .user ? Color.secondary.opacity(0.12) : Color.primary.opacity(0.03))
          .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .stroke(Color.primary.opacity(role == .user ? 0 : 0.12), lineWidth: 1)
          }
      }
  }
}
