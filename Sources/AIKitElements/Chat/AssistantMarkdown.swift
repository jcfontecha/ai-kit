import SwiftUI
import MarkdownUI

public struct AssistantMarkdownStyle: Sendable {
  public var lineSpacingEm: Double
  public var paragraphSpacingEm: Double
  public var listItemSpacingEm: Double
  public var contentPadding: CGFloat

  public init(
    lineSpacingEm: Double = 0.34,
    paragraphSpacingEm: Double = 0.6,
    listItemSpacingEm: Double = 0.35,
    contentPadding: CGFloat = 2
  ) {
    self.lineSpacingEm = lineSpacingEm
    self.paragraphSpacingEm = paragraphSpacingEm
    self.listItemSpacingEm = listItemSpacingEm
    self.contentPadding = contentPadding
  }
}

public struct AssistantMarkdown: View {
  public let text: String
  public var isSecondary: Bool
  public var style: AssistantMarkdownStyle

  public init(
    text: String,
    isSecondary: Bool = false,
    style: AssistantMarkdownStyle = .init()
  ) {
    self.text = text
    self.isSecondary = isSecondary
    self.style = style
  }

  public var body: some View {
    let view = Markdown(text)
      .markdownBlockStyle(\.paragraph) { configuration in
        configuration.label
          .relativeLineSpacing(.em(style.lineSpacingEm))
          .markdownMargin(top: .zero, bottom: .em(style.paragraphSpacingEm))
      }
      .markdownBlockStyle(\.listItem) { configuration in
        configuration.label
          .relativeLineSpacing(.em(style.lineSpacingEm))
          .markdownMargin(top: .zero, bottom: .em(style.listItemSpacingEm))
      }
      .padding(style.contentPadding)

    if isSecondary {
      view.markdownTextStyle { ForegroundColor(.secondary) }
    } else {
      view
    }
  }
}
