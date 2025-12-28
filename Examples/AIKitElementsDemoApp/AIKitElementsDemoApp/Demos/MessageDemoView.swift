import SwiftUI
import MarkdownUI
import AIKitElements

struct MessageDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      MessageBubble(role: .user) {
        UserBubble(text: "And I'm the user. Bubbles should not be glass by default.")
      }
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

private struct MessageBubble<Content: View>: View {
  let role: DemoRole
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack {
      if role == .user {
        Spacer(minLength: 24)
        content()
      } else {
        content()
        Spacer(minLength: 24)
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
