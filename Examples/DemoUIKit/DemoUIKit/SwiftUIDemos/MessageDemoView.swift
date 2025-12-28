import SwiftUI
import MarkdownUI

struct MessageDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      MessageBubble(role: .user, text: "And I'm the user. Bubbles should not be glass by default.")
      AssistantMarkdownMessage(markdown: assistantMarkdown)
      AssistantMarkdownMessage(markdown: "Assistant messages should be **unrestricted text** (no bubble).")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var assistantMarkdown: String {
    """
    Here’s a markdown response (rendered with **MarkdownUI**):

    - Lists
    - *Emphasis*
    - Links: [AIKit](https://github.com)

    ```swift
    struct Hello: View {
      var body: some View { Text(\"Hello\") }
    }
    ```

    > Keep the assistant content readable by avoiding bubbles/glass behind it.
    """
  }
}

private enum DemoRole { case user, assistant }

private struct MessageBubble: View {
  let role: DemoRole
  let text: String

  var body: some View {
    HStack {
      if role == .user {
        Spacer(minLength: 24)
        bubble
      } else {
        bubble
        Spacer(minLength: 24)
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

private struct AssistantMarkdownMessage: View {
  let markdown: String

  var body: some View {
    Markdown(markdown)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
  }
}

