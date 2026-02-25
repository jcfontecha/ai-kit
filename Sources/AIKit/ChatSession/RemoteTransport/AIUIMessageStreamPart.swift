import Foundation
import AIKitProviders

/// Typed representation of the UI message stream protocol (SSE v1) parts.
public enum AIUIMessageStreamPart: Sendable, Equatable {
  case start(messageID: String? = nil, messageMetadata: JSONValue? = nil)
  case startStep
  case finishStep

  case textStart(id: String, providerMetadata: ProviderMetadata? = nil)
  case textDelta(id: String, delta: String, providerMetadata: ProviderMetadata? = nil)
  case textEnd(id: String, providerMetadata: ProviderMetadata? = nil)

  case reasoningStart(id: String, providerMetadata: ProviderMetadata? = nil)
  case reasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata? = nil)
  case reasoningEnd(id: String, providerMetadata: ProviderMetadata? = nil)

  case file(AIUIMessageStreamFilePart)
  case sourceURL(AIUIMessageStreamSourceURLPart)
  case sourceDocument(AIUIMessageStreamSourceDocumentPart)

  case toolInputStart(ToolInputStart)
  case toolInputDelta(ToolInputDelta)
  case toolInputEnd(toolCallID: String)

  case toolInputAvailable(ToolInputAvailable)
  case toolInputError(ToolInputError)

  case toolApprovalRequest(approvalID: String, toolCallID: String)

  case toolOutputAvailable(ToolOutputAvailable)
  case toolOutputError(ToolOutputError)
  case toolOutputDenied(toolCallID: String)

  /// A `data-*` chunk as defined by the UI message stream protocol.
  case data(AIUIMessageStreamDataPart)

  case finish(finishReason: FinishReason? = nil, messageMetadata: JSONValue? = nil)
  case abort
  case messageMetadata(JSONValue)
  case error(String)

  /// Unknown or unsupported part; preserved for forward compatibility.
  case raw(JSONValue)
}

public struct AIUIMessageStreamDataPart: Sendable, Equatable {
  /// Full type string, e.g. `"data-foo"`.
  public var type: String
  public var id: String?
  public var data: JSONValue
  public var transient: Bool?

  public init(
    type: String,
    id: String? = nil,
    data: JSONValue,
    transient: Bool? = nil
  ) {
    self.type = type
    self.id = id
    self.data = data
    self.transient = transient
  }
}

public struct AIUIMessageStreamFilePart: Sendable, Equatable {
  public var url: String
  public var mediaType: String
  public var providerMetadata: ProviderMetadata?

  public init(
    url: String,
    mediaType: String,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.url = url
    self.mediaType = mediaType
    self.providerMetadata = providerMetadata
  }
}

public struct AIUIMessageStreamSourceURLPart: Sendable, Equatable {
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

public struct AIUIMessageStreamSourceDocumentPart: Sendable, Equatable {
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

public struct ToolInputStart: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var providerExecuted: Bool?
  public var dynamic: Bool?
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    toolCallID: String,
    toolName: String,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

public struct ToolInputDelta: Sendable, Equatable {
  public var toolCallID: String
  public var inputTextDelta: String
  public var providerMetadata: ProviderMetadata?

  public init(
    toolCallID: String,
    inputTextDelta: String,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.toolCallID = toolCallID
    self.inputTextDelta = inputTextDelta
    self.providerMetadata = providerMetadata
  }
}

public struct ToolInputAvailable: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var input: JSONValue
  public var providerExecuted: Bool?
  public var providerMetadata: ProviderMetadata?
  public var dynamic: Bool?
  public var title: String?

  public init(
    toolCallID: String,
    toolName: String,
    input: JSONValue,
    providerExecuted: Bool? = nil,
    providerMetadata: ProviderMetadata? = nil,
    dynamic: Bool? = nil,
    title: String? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.input = input
    self.providerExecuted = providerExecuted
    self.providerMetadata = providerMetadata
    self.dynamic = dynamic
    self.title = title
  }
}

public struct ToolInputError: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var input: JSONValue
  public var providerExecuted: Bool?
  public var providerMetadata: ProviderMetadata?
  public var dynamic: Bool?
  public var errorText: String
  public var title: String?

  public init(
    toolCallID: String,
    toolName: String,
    input: JSONValue,
    providerExecuted: Bool? = nil,
    providerMetadata: ProviderMetadata? = nil,
    dynamic: Bool? = nil,
    errorText: String,
    title: String? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.input = input
    self.providerExecuted = providerExecuted
    self.providerMetadata = providerMetadata
    self.dynamic = dynamic
    self.errorText = errorText
    self.title = title
  }
}

public struct ToolOutputAvailable: Sendable, Equatable {
  public var toolCallID: String
  public var output: JSONValue
  public var providerExecuted: Bool?
  public var dynamic: Bool?
  public var preliminary: Bool?

  public init(
    toolCallID: String,
    output: JSONValue,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    preliminary: Bool? = nil
  ) {
    self.toolCallID = toolCallID
    self.output = output
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.preliminary = preliminary
  }
}

public struct ToolOutputError: Sendable, Equatable {
  public var toolCallID: String
  public var errorText: String
  public var providerExecuted: Bool?
  public var dynamic: Bool?

  public init(
    toolCallID: String,
    errorText: String,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil
  ) {
    self.toolCallID = toolCallID
    self.errorText = errorText
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
  }
}
