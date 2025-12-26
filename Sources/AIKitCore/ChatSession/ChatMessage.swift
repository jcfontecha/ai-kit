import Foundation
import AIKitProviders

public struct ChatMessage: Sendable, Equatable, Identifiable {
  public var id: String
  public var role: MessageRole
  public var parts: [ChatMessagePart]
  public var metadata: JSONValue?

  public init(
    id: String,
    role: MessageRole,
    parts: [ChatMessagePart],
    metadata: JSONValue? = nil
  ) {
    self.id = id
    self.role = role
    self.parts = parts
    self.metadata = metadata
  }
}

public enum ChatMessagePart: Sendable, Equatable {
  case stepStart
  case text(ChatTextPart)
  case reasoning(ChatReasoningPart)
  case file(ChatFilePart)
  case sourceURL(ChatSourceURLPart)
  case sourceDocument(ChatSourceDocumentPart)
  case tool(ChatToolPart)
  case data(ChatDataPart)
}

public struct ChatSourceURLPart: Sendable, Equatable {
  public var sourceID: String
  public var url: String
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    sourceID: String,
    url: String,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.sourceID = sourceID
    self.url = url
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

public struct ChatSourceDocumentPart: Sendable, Equatable {
  public var sourceID: String
  public var mediaType: String
  public var title: String
  public var filename: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    sourceID: String,
    mediaType: String,
    title: String,
    filename: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.sourceID = sourceID
    self.mediaType = mediaType
    self.title = title
    self.filename = filename
    self.providerMetadata = providerMetadata
  }
}

public struct ChatDataPart: Sendable, Equatable {
  /// Full type string, e.g. `"data-foo"`.
  public var type: String
  public var id: String?
  public var data: JSONValue

  public init(
    type: String,
    id: String? = nil,
    data: JSONValue
  ) {
    self.type = type
    self.id = id
    self.data = data
  }
}

public struct ChatTextPart: Sendable, Equatable {
  public enum State: Sendable, Equatable { case streaming, done }
  public var id: String
  public var text: String
  public var state: State
  public var providerMetadata: ProviderMetadata?

  public init(
    id: String,
    text: String,
    state: State,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.id = id
    self.text = text
    self.state = state
    self.providerMetadata = providerMetadata
  }
}

public struct ChatReasoningPart: Sendable, Equatable {
  public enum State: Sendable, Equatable { case streaming, done }
  public var id: String
  public var text: String
  public var state: State
  public var providerMetadata: ProviderMetadata?

  public init(
    id: String,
    text: String,
    state: State,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.id = id
    self.text = text
    self.state = state
    self.providerMetadata = providerMetadata
  }
}

public struct ChatFilePart: Sendable, Equatable {
  public var data: DataContent
  public var filename: String?
  public var mediaType: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    data: DataContent,
    filename: String? = nil,
    mediaType: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.data = data
    self.filename = filename
    self.mediaType = mediaType
    self.providerMetadata = providerMetadata
  }
}

public struct ChatToolPart: Sendable, Equatable {
  public struct Approval: Sendable, Equatable {
    public var id: String
    public var approved: Bool?
    public var reason: String?

    public init(id: String, approved: Bool? = nil, reason: String? = nil) {
      self.id = id
      self.approved = approved
      self.reason = reason
    }
  }

  public enum State: Sendable, Equatable {
    case inputStreaming
    case inputAvailable

    case approvalRequested(approvalID: String)
    case approvalResponded(approvalID: String, approved: Bool, reason: String?)

    /// Mirrors the AI SDK UI message `output-denied` state, which requires an approval id (approved = false).
    /// `approvalID` can be `nil` only if the denial did not originate from an approval flow.
    case outputDenied(approvalID: String?, reason: String?)
    case outputAvailable(preliminary: Bool)
    case outputError(errorText: String)
  }

  public var toolCallID: String
  public var toolName: String
  public var title: String?
  public var approval: Approval?

  public var providerExecuted: Bool
  public var dynamic: Bool

  public var input: JSONValue?
  public var rawInput: JSONValue?
  public var output: JSONValue?

  public var callProviderMetadata: ProviderMetadata?
  public var state: State

  public init(
    toolCallID: String,
    toolName: String,
    title: String? = nil,
    providerExecuted: Bool = false,
    dynamic: Bool = false,
    input: JSONValue? = nil,
    rawInput: JSONValue? = nil,
    output: JSONValue? = nil,
    callProviderMetadata: ProviderMetadata? = nil,
    approval: Approval? = nil,
    state: State
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.title = title
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.input = input
    self.rawInput = rawInput
    self.output = output
    self.callProviderMetadata = callProviderMetadata
    self.approval = approval
    self.state = state
  }
}
