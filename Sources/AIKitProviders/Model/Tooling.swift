import Foundation

public struct ToolDefinition: Sendable, Equatable {
  public var name: String
  public var description: String?
  public var inputSchema: JSONSchema

  public init(name: String, description: String? = nil, inputSchema: JSONSchema) {
    self.name = name
    self.description = description
    self.inputSchema = inputSchema
  }
}

public struct ToolCall: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var inputJSON: String
  public var input: JSONValue?
  public var invalid: Bool?
  public var error: String?
  public var providerExecuted: Bool?
  public var dynamic: Bool?
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    toolCallID: String,
    toolName: String,
    inputJSON: String,
    input: JSONValue? = nil,
    invalid: Bool? = nil,
    error: String? = nil,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.inputJSON = inputJSON
    self.input = input
    self.invalid = invalid
    self.error = error
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

public struct ToolResult: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var inputJSON: String?
  public var input: JSONValue?
  public var output: JSONValue
  public var preliminary: Bool?
  public var providerExecuted: Bool?
  public var dynamic: Bool?
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    toolCallID: String,
    toolName: String,
    inputJSON: String? = nil,
    input: JSONValue? = nil,
    output: JSONValue,
    preliminary: Bool? = nil,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.inputJSON = inputJSON
    self.input = input
    self.output = output
    self.preliminary = preliminary
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

public struct ToolError: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var inputJSON: String?
  public var input: JSONValue?
  public var error: String
  public var providerExecuted: Bool?
  public var dynamic: Bool?
  public var title: String?
  public var providerMetadata: ProviderMetadata?

  public init(
    toolCallID: String,
    toolName: String,
    inputJSON: String? = nil,
    input: JSONValue? = nil,
    error: String,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.inputJSON = inputJSON
    self.input = input
    self.error = error
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.title = title
    self.providerMetadata = providerMetadata
  }
}

public struct ToolOutputDenied: Sendable, Equatable {
  public var toolCallID: String
  public var toolName: String
  public var providerExecuted: Bool?
  public var dynamic: Bool?

  public init(
    toolCallID: String,
    toolName: String,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
  }
}
