import SwiftUI

public struct ChatTheme: Sendable {
  public enum ControlVisibility: Sendable {
    case disabled
    case hidden
  }

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

  public struct ControlTheme: Sendable {
    public var foreground: Color?
    public var background: Color?

    public init(
      foreground: Color? = nil,
      background: Color? = nil
    ) {
      self.foreground = foreground
      self.background = background
    }
  }

  public struct AddButtonTheme: Sendable {
    public var unavailableVisibility: ControlVisibility?

    public init(unavailableVisibility: ControlVisibility? = nil) {
      self.unavailableVisibility = unavailableVisibility
    }
  }

  public struct BubbleTheme: Sendable {
    public var background: Color?

    public init(background: Color? = nil) {
      self.background = background
    }
  }

  public struct ComposerTheme: Sendable {
    public var sendButton: ControlTheme?
    public var addButton: AddButtonTheme?
    public var surfaceTint: Color?

    public init(
      sendButton: ControlTheme? = nil,
      addButton: AddButtonTheme? = nil,
      surfaceTint: Color? = nil
    ) {
      self.sendButton = sendButton
      self.addButton = addButton
      self.surfaceTint = surfaceTint
    }
  }

  public struct MessageTheme: Sendable {
    public var userBubble: BubbleTheme?

    public init(userBubble: BubbleTheme? = nil) {
      self.userBubble = userBubble
    }
  }

  public var composer: ComposerTheme
  public var message: MessageTheme
  public var spacing: Spacing
  public var tool: Tool
  public var markdown: Markdown

  public init(
    composer: ComposerTheme = .init(),
    message: MessageTheme = .init(),
    spacing: Spacing = .init(),
    tool: Tool = .init(),
    markdown: Markdown = .init()
  ) {
    self.composer = composer
    self.message = message
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
