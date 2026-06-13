import SwiftUI

public struct ChatTheme: Sendable {
  public struct Spacing: Sendable {
    public var messageRow: CGFloat
    public var messageStack: CGFloat
    public var contentPadding: EdgeInsets

    public init(
      messageRow: CGFloat = 16,
      messageStack: CGFloat = 32,
      contentPadding: EdgeInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
    ) {
      self.messageRow = messageRow
      self.messageStack = messageStack
      self.contentPadding = contentPadding
    }
  }

  public struct Tool: Sendable {
    public var defaultStatusStrings: ToolStatusStrings

    public init(defaultStatusStrings: ToolStatusStrings = .standard) {
      self.defaultStatusStrings = defaultStatusStrings
    }
  }

  public struct Markdown: Sendable {
    public var style: AssistantMarkdownStyle

    public init(style: AssistantMarkdownStyle = .init()) {
      self.style = style
    }
  }

  public struct Colors: Sendable {
    public var sendButtonForeground: Color?
    public var sendButtonBackground: Color?
    public var userBubbleBackground: Color?

    public init(
      sendButtonForeground: Color? = nil,
      sendButtonBackground: Color? = nil,
      userBubbleBackground: Color? = nil
    ) {
      self.sendButtonForeground = sendButtonForeground
      self.sendButtonBackground = sendButtonBackground
      self.userBubbleBackground = userBubbleBackground
    }
  }

  public var colors: Colors
  public var spacing: Spacing
  public var tool: Tool
  public var markdown: Markdown

  public init(
    colors: Colors = .init(),
    spacing: Spacing = .init(),
    tool: Tool = .init(),
    markdown: Markdown = .init()
  ) {
    self.colors = colors
    self.spacing = spacing
    self.tool = tool
    self.markdown = markdown
  }

  public static let standard = ChatTheme()
}

private struct ChatThemeKey: EnvironmentKey {
  static let defaultValue: ChatTheme = .standard
}

public extension EnvironmentValues {
  var chatTheme: ChatTheme {
    get { self[ChatThemeKey.self] }
    set { self[ChatThemeKey.self] = newValue }
  }
}

public extension View {
  func chatTheme(_ theme: ChatTheme) -> some View {
    environment(\.chatTheme, theme)
  }
}
