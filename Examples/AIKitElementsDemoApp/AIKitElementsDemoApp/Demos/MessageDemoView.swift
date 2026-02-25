import SwiftUI
import MarkdownUI
import AIKit
import AIKitElements

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct MessageDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      MessageBubble(role: .user) {
        VStack(alignment: .trailing, spacing: 8) {
          FileAttachmentPreviewRow(attachments: sampleAttachments, size: 44, cornerRadius: 10, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
          UserBubble(text: "And I'm the user. Bubbles should not be glass by default.")
        }
      }
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

  private var sampleAttachments: [ChatFilePart] {
    [
      .init(data: .data(demoSymbolData("photo") ?? Data()), filename: "Image.png", mediaType: "image/png"),
      .init(data: .data(demoSymbolData("doc") ?? Data()), filename: "Notes.pdf", mediaType: "application/pdf"),
    ]
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

#if canImport(AppKit)
private func demoSymbolData(_ name: String) -> Data? {
  guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff) else { return nil }
  return rep.representation(using: .png, properties: [:])
}
#elseif canImport(UIKit)
private func demoSymbolData(_ name: String) -> Data? {
  UIImage(systemName: name)?.pngData()
}
#endif
