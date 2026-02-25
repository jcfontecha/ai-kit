import Foundation
import AIKitProviders

public enum AIUIMessageDecodingError: Error, LocalizedError, Sendable, Equatable {
  case invalidJSON
  case invalidRole(String)
  case invalidMessageParts(messageID: String)
  case invalidPartType
  case invalidURL(String)
  case missingApprovalID(toolCallID: String, state: String)

  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      return "Invalid JSON payload."
    case .invalidRole(let role):
      return "Invalid UIMessage role: \(role)"
    case .invalidMessageParts(let messageID):
      return "Invalid UIMessage parts for message \(messageID)."
    case .invalidPartType:
      return "Invalid UIMessage part type."
    case .invalidURL(let url):
      return "Invalid URL: \(url)"
    case .missingApprovalID(let toolCallID, let state):
      return "Tool part \(toolCallID) is missing approval.id for state \(state)."
    }
  }
}

/// Decodes UI `UIMessage[]` JSON into AIKit `ChatMessage[]`.
public struct AIUIMessageDecoder: Sendable {
  public init() {}

  public func decodeJSONData(
    _ data: Data,
    validateMessageMetadata: (@Sendable (JSONValue?) async throws -> Void)? = nil,
    validateDataParts: [String: @Sendable (JSONValue) async throws -> Void]? = nil
  ) async throws -> [ChatMessage] {
    let messages: [AIUIMessage]
    do {
      messages = try JSONDecoder().decode([AIUIMessage].self, from: data)
    } catch {
      throw AIUIMessageDecodingError.invalidJSON
    }

    return try await decode(
      messages,
      validateMessageMetadata: validateMessageMetadata,
      validateDataParts: validateDataParts
    )
  }

  public func decode(
    _ messages: [AIUIMessage],
    validateMessageMetadata: (@Sendable (JSONValue?) async throws -> Void)? = nil,
    validateDataParts: [String: @Sendable (JSONValue) async throws -> Void]? = nil
  ) async throws -> [ChatMessage] {
    var result: [ChatMessage] = []
    result.reserveCapacity(messages.count)

    for message in messages {
      let role: MessageRole
      switch message.role {
      case "system": role = .system
      case "user": role = .user
      case "assistant": role = .assistant
      default:
        throw AIUIMessageDecodingError.invalidRole(message.role)
      }

      try await validateMessageMetadata?(message.metadata)

      var parts: [ChatMessagePart] = []
      parts.reserveCapacity(message.parts.count)

      for (index, partValue) in message.parts.enumerated() {
        guard case let .object(obj) = partValue else {
          throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
        }
        guard let type = obj["type"]?.stringValue else { throw AIUIMessageDecodingError.invalidPartType }

        switch type {
        case "step-start":
          parts.append(.stepStart)

        case "text":
          let text = obj["text"]?.stringValue ?? ""
          let stateRaw = obj["state"]?.stringValue
          let state: ChatTextPart.State = (stateRaw == "streaming") ? .streaming : .done
          let providerMetadata = obj["providerMetadata"]?.providerMetadataValue
          parts.append(.text(.init(
            id: "ui-text-\(index)",
            text: text,
            state: state,
            providerMetadata: providerMetadata
          )))

        case "reasoning":
          let text = obj["text"]?.stringValue ?? ""
          let stateRaw = obj["state"]?.stringValue
          let state: ChatReasoningPart.State = (stateRaw == "streaming") ? .streaming : .done
          let providerMetadata = obj["providerMetadata"]?.providerMetadataValue
          parts.append(.reasoning(.init(
            id: "ui-reasoning-\(index)",
            text: text,
            state: state,
            providerMetadata: providerMetadata
          )))

        case "file":
          guard let urlString = obj["url"]?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          guard let url = URL(string: urlString) else { throw AIUIMessageDecodingError.invalidURL(urlString) }
          let mediaType = obj["mediaType"]?.stringValue
          let filename = obj["filename"]?.stringValue
          let providerMetadata = obj["providerMetadata"]?.providerMetadataValue
          parts.append(.file(.init(
            data: .url(url),
            filename: filename,
            mediaType: mediaType,
            providerMetadata: providerMetadata
          )))

        case "source-url":
          guard let sourceID = (obj["sourceId"] ?? obj["sourceID"])?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          guard let url = obj["url"]?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          let title = obj["title"]?.stringValue
          let providerMetadata = obj["providerMetadata"]?.providerMetadataValue
          parts.append(.sourceURL(.init(sourceID: sourceID, url: url, title: title, providerMetadata: providerMetadata)))

        case "source-document":
          guard let sourceID = (obj["sourceId"] ?? obj["sourceID"])?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          guard let mediaType = obj["mediaType"]?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          guard let title = obj["title"]?.stringValue else {
            throw AIUIMessageDecodingError.invalidMessageParts(messageID: message.id)
          }
          let filename = obj["filename"]?.stringValue
          let providerMetadata = obj["providerMetadata"]?.providerMetadataValue
          parts.append(.sourceDocument(.init(
            sourceID: sourceID,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
          )))

        default:
          if type.hasPrefix("data-") {
            let id = obj["id"]?.stringValue
            let data = obj["data"] ?? .null
            if let validator = validateDataParts?[type] {
              try await validator(data)
            }
            parts.append(.data(.init(type: type, id: id, data: data)))
            continue
          }

          if type == "dynamic-tool" || type.hasPrefix("tool-") {
            let tool = try decodeToolPart(obj: obj, type: type)
            parts.append(.tool(tool))
            continue
          }

          // Preserve forward compatibility by ignoring unknown parts (validation would reject, but decoding can be looser).
          continue
        }
      }

      result.append(.init(id: message.id, role: role, parts: parts, metadata: message.metadata))
    }

    return result
  }

  private func decodeToolPart(obj: [String: JSONValue], type: String) throws -> ChatToolPart {
    let dynamic = (type == "dynamic-tool")
    let toolName: String = {
      if dynamic {
        return obj["toolName"]?.stringValue ?? "unknown"
      }
      if type.hasPrefix("tool-") {
        return String(type.dropFirst(5))
      }
      return "unknown"
    }()

    guard let toolCallID = (obj["toolCallId"] ?? obj["toolCallID"])?.stringValue else {
      throw AIUIMessageDecodingError.invalidPartType
    }

    let title = obj["title"]?.stringValue
    let providerExecuted = obj["providerExecuted"]?.boolValue ?? false
    let callProviderMetadata = obj["callProviderMetadata"]?.providerMetadataValue

    let approvalObj = obj["approval"]
    let approval: ChatToolPart.Approval? = {
      guard case let .object(a)? = approvalObj else { return nil }
      guard let id = a["id"]?.stringValue else { return nil }
      let approved = a["approved"]?.boolValue
      let reason = a["reason"]?.stringValue
      return .init(id: id, approved: approved, reason: reason)
    }()

    let stateRaw = obj["state"]?.stringValue ?? "input-streaming"

    let input = obj["input"]
    let rawInput = obj["rawInput"]
    let output = obj["output"]
    let errorText = obj["errorText"]?.stringValue
    let preliminary = obj["preliminary"]?.boolValue ?? false

    let state: ChatToolPart.State
    switch stateRaw {
    case "input-streaming":
      state = .inputStreaming
    case "input-available":
      state = .inputAvailable
    case "approval-requested":
      guard let approvalID = approval?.id, approvalID.isEmpty == false else {
        throw AIUIMessageDecodingError.missingApprovalID(toolCallID: toolCallID, state: stateRaw)
      }
      state = .approvalRequested(approvalID: approvalID)
    case "approval-responded":
      guard let approvalID = approval?.id, approvalID.isEmpty == false else {
        throw AIUIMessageDecodingError.missingApprovalID(toolCallID: toolCallID, state: stateRaw)
      }
      state = .approvalResponded(approvalID: approvalID, approved: approval?.approved ?? false, reason: approval?.reason)
    case "output-available":
      state = .outputAvailable(preliminary: preliminary)
    case "output-error":
      state = .outputError(errorText: errorText ?? "Unknown tool error")
    case "output-denied":
      guard let approvalID = approval?.id, approvalID.isEmpty == false else {
        throw AIUIMessageDecodingError.missingApprovalID(toolCallID: toolCallID, state: stateRaw)
      }
      state = .outputDenied(approvalID: approvalID, reason: approval?.reason)
    default:
      state = .inputStreaming
    }

    return .init(
      toolCallID: toolCallID,
      toolName: toolName,
      title: title,
      providerExecuted: providerExecuted,
      dynamic: dynamic,
      input: input,
      rawInput: rawInput,
      output: output,
      callProviderMetadata: callProviderMetadata,
      approval: approval,
      state: state
    )
  }
}

private extension JSONValue {
  var stringValue: String? {
    guard case let .string(value) = self else { return nil }
    return value
  }

  var boolValue: Bool? {
    guard case let .bool(value) = self else { return nil }
    return value
  }

  var providerMetadataValue: ProviderMetadata? {
    guard case let .object(obj) = self else { return nil }
    return obj
  }
}
