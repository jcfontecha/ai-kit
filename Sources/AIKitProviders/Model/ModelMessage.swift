import Foundation

public struct MessageTextPart: Sendable, Equatable, ExpressibleByStringLiteral {
  public var text: String
  public var providerOptions: ProviderOptions?

  public init(text: String, providerOptions: ProviderOptions? = nil) {
    self.text = text
    self.providerOptions = providerOptions
  }

  public init(stringLiteral value: String) {
    self.text = value
    self.providerOptions = nil
  }
}

public struct MessageReasoningPart: Sendable, Equatable, ExpressibleByStringLiteral {
  public var text: String
  public var providerOptions: ProviderOptions?

  public init(text: String, providerOptions: ProviderOptions? = nil) {
    self.text = text
    self.providerOptions = providerOptions
  }

  public init(stringLiteral value: String) {
    self.text = value
    self.providerOptions = nil
  }
}

public enum ModelMessagePart: Sendable, Equatable {
  case text(MessageTextPart)
  case image(ImageContent)
  case file(FileContent)
  case reasoning(MessageReasoningPart)
  case toolCall(ToolCall)
  case toolResult(ToolResult)
  case toolError(ToolError)
  case toolOutputDenied(ToolOutputDenied)
  case toolApprovalRequest(ToolApprovalRequest)
  case toolApprovalResponse(ToolApprovalResponse)
}

public struct ModelMessage: Sendable, Equatable {
  public var role: MessageRole
  public var content: [ModelMessagePart]
  /// Provider-specific options attached to this message (input).
  public var providerOptions: ProviderOptions?
  /// Provider-specific metadata attached to this message (output).
  public var providerMetadata: ProviderMetadata?

  public init(
    role: MessageRole,
    content: [ModelMessagePart],
    providerOptions: ProviderOptions? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.role = role
    self.content = content
    self.providerOptions = providerOptions
    self.providerMetadata = providerMetadata
  }

  public static func system(
    _ text: String,
    providerOptions: ProviderOptions? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) -> Self {
    .init(
      role: .system,
      content: [.text(.init(text: text))],
      providerOptions: providerOptions,
      providerMetadata: providerMetadata
    )
  }

  public static func user(
    _ text: String,
    providerOptions: ProviderOptions? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) -> Self {
    .init(
      role: .user,
      content: [.text(.init(text: text))],
      providerOptions: providerOptions,
      providerMetadata: providerMetadata
    )
  }

  public static func assistant(
    _ text: String,
    providerOptions: ProviderOptions? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) -> Self {
    .init(
      role: .assistant,
      content: [.text(.init(text: text))],
      providerOptions: providerOptions,
      providerMetadata: providerMetadata
    )
  }
}
