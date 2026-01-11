import Foundation
import AIKitProviders

public enum AIUIMessageEncodingError: Error, LocalizedError, Sendable, Equatable {
  case unsupportedRole(MessageRole)
  case filePartMissingMediaType(messageID: String)
  case toolPartMissingInput(toolCallID: String, state: String)
  case toolPartMissingOutput(toolCallID: String)
  case toolOutputDeniedMissingApprovalID(toolCallID: String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedRole(let role):
      return "Unsupported role for AI SDK UIMessage encoding: \(role)"
    case .filePartMissingMediaType(let messageID):
      return "File part is missing mediaType for message \(messageID)."
    case .toolPartMissingInput(let toolCallID, let state):
      return "Tool part \(toolCallID) is missing required input for state \(state)."
    case .toolPartMissingOutput(let toolCallID):
      return "Tool part \(toolCallID) is missing required output."
    case .toolOutputDeniedMissingApprovalID(let toolCallID):
      return "Tool part \(toolCallID) is in outputDenied state but is missing the approval id required by AI SDK UIMessage `output-denied`."
    }
  }
}

/// Encodes AIKit `ChatMessage[]` into AI SDK UI `UIMessage[]` JSON for Node endpoints.
///
/// Source of truth: `ai-sdk/packages/ai/src/ui/ui-messages.ts`.
public struct AIUIMessageEncoder: Sendable {
  public var ignoreIncompleteToolCalls: Bool

  public init(ignoreIncompleteToolCalls: Bool = false) {
    self.ignoreIncompleteToolCalls = ignoreIncompleteToolCalls
  }

  public func encode(_ messages: [ChatMessage]) throws -> [AIUIMessage] {
    try messages.map(encodeMessage(_:))
  }

  private func encodeMessage(_ message: ChatMessage) throws -> AIUIMessage {
    let role: String
    switch message.role {
    case .system: role = "system"
    case .user: role = "user"
    case .assistant: role = "assistant"
    case .tool:
      throw AIUIMessageEncodingError.unsupportedRole(.tool)
    }

    var parts: [JSONValue] = []
    parts.reserveCapacity(message.parts.count)
    for part in message.parts where shouldInclude(part) {
      parts.append(try encodePart(part, messageID: message.id))
    }
    return .init(id: message.id, role: role, metadata: message.metadata, parts: parts)
  }

  private func shouldInclude(_ part: ChatMessagePart) -> Bool {
    guard ignoreIncompleteToolCalls else { return true }
    guard case let .tool(tool) = part else { return true }
    switch tool.state {
    case .inputStreaming, .inputAvailable:
      return false
    default:
      return true
    }
  }

  private func encodePart(_ part: ChatMessagePart, messageID: String) throws -> JSONValue {
    switch part {
    case .stepStart:
      return .object(["type": .string("step-start")])

    case .text(let text):
      var obj: [String: JSONValue] = [
        "type": .string("text"),
        "text": .string(text.text),
        "state": .string(text.state == .streaming ? "streaming" : "done"),
      ]
      if let providerMetadata = text.providerMetadata {
        obj["providerMetadata"] = .object(providerMetadata)
      }
      return .object(obj)

    case .reasoning(let reasoning):
      var obj: [String: JSONValue] = [
        "type": .string("reasoning"),
        "text": .string(reasoning.text),
        "state": .string(reasoning.state == .streaming ? "streaming" : "done"),
      ]
      if let providerMetadata = reasoning.providerMetadata {
        obj["providerMetadata"] = .object(providerMetadata)
      }
      return .object(obj)

    case .file(let file):
      guard let mediaType = file.mediaType else {
        throw AIUIMessageEncodingError.filePartMissingMediaType(messageID: messageID)
      }

      var obj: [String: JSONValue] = [
        "type": .string("file"),
        "mediaType": .string(mediaType),
        "url": .string(try encodeDataContentAsURLString(file.data, mediaType: mediaType)),
      ]
      if let filename = file.filename {
        obj["filename"] = .string(filename)
      }
      if let providerMetadata = file.providerMetadata {
        obj["providerMetadata"] = .object(providerMetadata)
      }
      return .object(obj)

    case .tool(let tool):
      return try encodeToolPart(tool)

    case .data(let data):
      var obj: [String: JSONValue] = [
        "type": .string(data.type),
        "data": data.data,
      ]
      if let id = data.id {
        obj["id"] = .string(id)
      }
      return .object(obj)

    case .sourceURL(let source):
      var obj: [String: JSONValue] = [
        "type": .string("source-url"),
        "sourceId": .string(source.sourceID),
        "url": .string(source.url),
      ]
      if let title = source.title {
        obj["title"] = .string(title)
      }
      if let providerMetadata = source.providerMetadata {
        obj["providerMetadata"] = .object(providerMetadata)
      }
      return .object(obj)

    case .sourceDocument(let source):
      var obj: [String: JSONValue] = [
        "type": .string("source-document"),
        "sourceId": .string(source.sourceID),
        "mediaType": .string(source.mediaType),
        "title": .string(source.title),
      ]
      if let filename = source.filename {
        obj["filename"] = .string(filename)
      }
      if let providerMetadata = source.providerMetadata {
        obj["providerMetadata"] = .object(providerMetadata)
      }
      return .object(obj)
    }
  }

  private func encodeToolPart(_ tool: ChatToolPart) throws -> JSONValue {
    var obj: [String: JSONValue] = [
      "toolCallId": .string(tool.toolCallID),
      "title": tool.title.map(JSONValue.string) ?? .null,
      "providerExecuted": .bool(tool.providerExecuted),
    ]

    if tool.dynamic {
      obj["type"] = .string("dynamic-tool")
      obj["toolName"] = .string(tool.toolName)
    } else {
      obj["type"] = .string("tool-\(tool.toolName)")
    }

    if let callProviderMetadata = tool.callProviderMetadata {
      obj["callProviderMetadata"] = .object(callProviderMetadata)
    }

    switch tool.state {
    case .inputStreaming:
      obj["state"] = .string("input-streaming")
      if let input = tool.input {
        obj["input"] = input
      }
      return .object(compactNulls(obj))

    case .inputAvailable:
      obj["state"] = .string("input-available")
      guard let input = tool.input ?? tool.rawInput else {
        throw AIUIMessageEncodingError.toolPartMissingInput(toolCallID: tool.toolCallID, state: "input-available")
      }
      obj["input"] = input
      return .object(compactNulls(obj))

    case .approvalRequested(let approvalID):
      obj["state"] = .string("approval-requested")
      guard let input = tool.input ?? tool.rawInput else {
        throw AIUIMessageEncodingError.toolPartMissingInput(toolCallID: tool.toolCallID, state: "approval-requested")
      }
      obj["input"] = input
      obj["approval"] = .object(["id": .string(approvalID)])
      return .object(compactNulls(obj))

    case .approvalResponded(let approvalID, let approved, let reason):
      obj["state"] = .string("approval-responded")
      guard let input = tool.input ?? tool.rawInput else {
        throw AIUIMessageEncodingError.toolPartMissingInput(toolCallID: tool.toolCallID, state: "approval-responded")
      }
      obj["input"] = input
      var approval: [String: JSONValue] = [
        "id": .string(approvalID),
        "approved": .bool(approved),
      ]
      if let reason {
        approval["reason"] = .string(reason)
      }
      obj["approval"] = .object(approval)
      return .object(compactNulls(obj))

    case .outputAvailable(let preliminary):
      obj["state"] = .string("output-available")
      guard let input = tool.input ?? tool.rawInput else {
        throw AIUIMessageEncodingError.toolPartMissingInput(toolCallID: tool.toolCallID, state: "output-available")
      }
      guard let output = tool.output else {
        throw AIUIMessageEncodingError.toolPartMissingOutput(toolCallID: tool.toolCallID)
      }
      obj["input"] = input
      obj["output"] = output
      obj["preliminary"] = .bool(preliminary)
      return .object(compactNulls(obj))

    case .outputError(let errorText):
      obj["state"] = .string("output-error")
      obj["errorText"] = .string(errorText)
      if let input = tool.input {
        obj["input"] = input
      }
      if let rawInput = tool.rawInput {
        obj["rawInput"] = rawInput
      }
      return .object(compactNulls(obj))

    case .outputDenied(let approvalID, let reason):
      obj["state"] = .string("output-denied")
      guard let input = tool.input ?? tool.rawInput else {
        throw AIUIMessageEncodingError.toolPartMissingInput(toolCallID: tool.toolCallID, state: "output-denied")
      }
      guard let approvalID else {
        throw AIUIMessageEncodingError.toolOutputDeniedMissingApprovalID(toolCallID: tool.toolCallID)
      }
      obj["input"] = input
      var approval: [String: JSONValue] = [
        "id": .string(approvalID),
        "approved": .bool(false),
      ]
      if let reason {
        approval["reason"] = .string(reason)
      }
      obj["approval"] = .object(approval)
      return .object(compactNulls(obj))
    }
  }

  private func encodeDataContentAsURLString(_ data: DataContent, mediaType: String) throws -> String {
    switch data {
    case .url(let url):
      return url.absoluteString
    case .base64(let base64):
      return "data:\(mediaType);base64,\(base64)"
    case .data(let data):
      return "data:\(mediaType);base64,\(data.base64EncodedString())"
    }
  }

  private func compactNulls(_ object: [String: JSONValue]) -> [String: JSONValue] {
    object.filter { _, value in
      if case .null = value { return false }
      return true
    }
  }
}
