import Foundation
import AIKitProviders

public enum SSEUIMessageStreamDecoderError: Error, LocalizedError, Sendable, Equatable {
  case invalidUTF8
  case invalidJSON(String)

  public var errorDescription: String? {
    switch self {
    case .invalidUTF8:
      return "Invalid UTF-8 in SSE payload."
    case .invalidJSON(let payload):
      return "Invalid JSON in SSE payload: \(payload)"
    }
  }
}

public struct SSEEvent: Sendable, Equatable {
  public var id: String?
  public var data: String

  public init(id: String? = nil, data: String) {
    self.id = id
    self.data = data
  }
}

public struct SSEUIMessageStreamDecoder: Sendable {
  public init() {}

  public func decode<S: AsyncSequence>(
    _ bytes: S
  ) -> AsyncThrowingStream<AIUIMessageStreamPart, Error> where S.Element == UInt8 {
    let events = Self.decodeSSEEvents(bytes)
    return AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
      Task {
        do {
          for try await event in events {
            let trimmed = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "[DONE]" {
              continuation.finish()
              return
            }

            let json = try Self.parseJSONValue(fromUTF8String: event.data)
            guard case let .object(object) = json,
                  case let .string(type) = object["type"]
            else {
              continuation.yield(.raw(json))
              continue
            }

            continuation.yield(Self.mapUIStreamPart(type: type, payload: object, raw: json))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private static func decodeSSEEvents<S: AsyncSequence>(
    _ bytes: S
  ) -> AsyncThrowingStream<SSEEvent, Error> where S.Element == UInt8 {
    AsyncThrowingStream(SSEEvent.self) { continuation in
      Task {
        var buffer = Data()
        do {
          for try await byte in bytes {
            buffer.append(byte)
            while let range = nextSSEChunkRange(in: buffer) {
              let chunkData = buffer.subdata(in: 0..<range.lowerBound)
              buffer.removeSubrange(0..<range.upperBound)
              if let event = parseSSEChunk(chunkData) {
                continuation.yield(event)
              }
            }
          }

          if buffer.isEmpty == false, let event = parseSSEChunk(buffer) {
            continuation.yield(event)
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private static func nextSSEChunkRange(in buffer: Data) -> Range<Data.Index>? {
    // Accept both LF and CRLF delimiters.
    if let lf = buffer.range(of: Data([0x0A, 0x0A])) {
      return lf
    }
    if let crlf = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
      return crlf
    }
    return nil
  }

  private static func parseSSEChunk(_ data: Data) -> SSEEvent? {
    guard let string = String(data: data, encoding: .utf8) else { return nil }
    let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
    var dataLines: [String] = []
    var lastID: String?

    for line in lines {
      if line.hasPrefix("data:") {
        let payload = line.dropFirst(5)
        let trimmed = payload.first == " " ? payload.dropFirst() : Substring(payload)
        dataLines.append(String(trimmed))
      } else if line.hasPrefix("id:") {
        let payload = line.dropFirst(3)
        let trimmed = payload.first == " " ? payload.dropFirst() : Substring(payload)
        lastID = String(trimmed)
      }
    }

    guard dataLines.isEmpty == false else { return nil }
    return .init(id: lastID, data: dataLines.joined(separator: "\n"))
  }

  private static func parseJSONValue(fromUTF8String payload: String) throws -> JSONValue {
    guard let data = payload.data(using: .utf8) else {
      throw SSEUIMessageStreamDecoderError.invalidUTF8
    }
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    if let json = JSONValue.from(object) {
      return json
    }
    throw SSEUIMessageStreamDecoderError.invalidJSON(payload)
  }

  private static func mapUIStreamPart(
    type: String,
    payload: [String: JSONValue],
    raw: JSONValue
  ) -> AIUIMessageStreamPart {
    switch type {
    case "start":
      let messageID = payload["messageId"]?.stringValue ?? payload["messageID"]?.stringValue
      let messageMetadata = payload["messageMetadata"]
      return .start(messageID: messageID, messageMetadata: messageMetadata)

    case "start-step":
      return .startStep

    case "finish-step":
      return .finishStep

    case "text-start":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .textStart(id: id, providerMetadata: providerMetadata)

    case "text-delta":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let delta = payload["delta"]?.stringValue ?? ""
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)

    case "text-end":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .textEnd(id: id, providerMetadata: providerMetadata)

    case "reasoning-start":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .reasoningStart(id: id, providerMetadata: providerMetadata)

    case "reasoning-delta":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let delta = payload["delta"]?.stringValue ?? ""
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)

    case "reasoning-end":
      guard let id = payload["id"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .reasoningEnd(id: id, providerMetadata: providerMetadata)

    case "file":
      guard let url = payload["url"]?.stringValue else { return .raw(raw) }
      guard let mediaType = payload["mediaType"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .file(.init(url: url, mediaType: mediaType, providerMetadata: providerMetadata))

    case "source-url":
      guard let sourceID = payload["sourceId"]?.stringValue ?? payload["sourceID"]?.stringValue else { return .raw(raw) }
      guard let url = payload["url"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .sourceURL(.init(
        sourceID: sourceID,
        url: url,
        title: payload["title"]?.stringValue,
        providerMetadata: providerMetadata
      ))

    case "source-document":
      guard let sourceID = payload["sourceId"]?.stringValue ?? payload["sourceID"]?.stringValue else { return .raw(raw) }
      guard let mediaType = payload["mediaType"]?.stringValue else { return .raw(raw) }
      guard let title = payload["title"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .sourceDocument(.init(
        sourceID: sourceID,
        mediaType: mediaType,
        title: title,
        filename: payload["filename"]?.stringValue,
        providerMetadata: providerMetadata
      ))

    case "tool-input-start":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      guard let toolName = payload["toolName"]?.stringValue else { return .raw(raw) }
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .toolInputStart(.init(
        toolCallID: toolCallID,
        toolName: toolName,
        providerExecuted: payload["providerExecuted"]?.boolValue,
        dynamic: payload["dynamic"]?.boolValue,
        title: payload["title"]?.stringValue,
        providerMetadata: providerMetadata
      ))

    case "tool-input-delta":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      let delta = payload["inputTextDelta"]?.stringValue ?? payload["delta"]?.stringValue ?? ""
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .toolInputDelta(.init(toolCallID: toolCallID, inputTextDelta: delta, providerMetadata: providerMetadata))

    case "tool-input-end":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      return .toolInputEnd(toolCallID: toolCallID)

    case "tool-input-available":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      guard let toolName = payload["toolName"]?.stringValue else { return .raw(raw) }
      let input = payload["input"] ?? .null
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .toolInputAvailable(.init(
        toolCallID: toolCallID,
        toolName: toolName,
        input: input,
        providerExecuted: payload["providerExecuted"]?.boolValue,
        providerMetadata: providerMetadata,
        dynamic: payload["dynamic"]?.boolValue,
        title: payload["title"]?.stringValue
      ))

    case "tool-input-error":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      guard let toolName = payload["toolName"]?.stringValue else { return .raw(raw) }
      let input = payload["input"] ?? .null
      let errorText = payload["errorText"]?.stringValue ?? "Unknown tool input error"
      let providerMetadata = decodeCodable(ProviderMetadata.self, from: payload["providerMetadata"])
      return .toolInputError(.init(
        toolCallID: toolCallID,
        toolName: toolName,
        input: input,
        providerExecuted: payload["providerExecuted"]?.boolValue,
        providerMetadata: providerMetadata,
        dynamic: payload["dynamic"]?.boolValue,
        errorText: errorText,
        title: payload["title"]?.stringValue
      ))

    case "tool-output-available":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      let output = payload["output"] ?? .null
      return .toolOutputAvailable(.init(
        toolCallID: toolCallID,
        output: output,
        providerExecuted: payload["providerExecuted"]?.boolValue,
        dynamic: payload["dynamic"]?.boolValue,
        preliminary: payload["preliminary"]?.boolValue
      ))

    case "tool-output-error":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      let errorText = payload["errorText"]?.stringValue ?? "Unknown tool output error"
      return .toolOutputError(.init(
        toolCallID: toolCallID,
        errorText: errorText,
        providerExecuted: payload["providerExecuted"]?.boolValue,
        dynamic: payload["dynamic"]?.boolValue
      ))

    case "tool-output-denied":
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      return .toolOutputDenied(toolCallID: toolCallID)

    case "tool-approval-request":
      guard let approvalID = payload["approvalId"]?.stringValue ?? payload["approvalID"]?.stringValue else { return .raw(raw) }
      guard let toolCallID = payload["toolCallId"]?.stringValue ?? payload["toolCallID"]?.stringValue else { return .raw(raw) }
      return .toolApprovalRequest(approvalID: approvalID, toolCallID: toolCallID)

    case "error":
      let errorText = payload["errorText"]?.stringValue ?? payload["message"]?.stringValue ?? "Unknown error"
      return .error(errorText)

    case "finish":
      let finishReason = parseFinishReason(payload["finishReason"])
      let messageMetadata = payload["messageMetadata"]
      return .finish(finishReason: finishReason, messageMetadata: messageMetadata)

    case "abort":
      return .abort

    case "message-metadata":
      guard let messageMetadata = payload["messageMetadata"] else { return .raw(raw) }
      return .messageMetadata(messageMetadata)

    default:
      if type.hasPrefix("data-") {
        let id = payload["id"]?.stringValue
        let data = payload["data"] ?? .null
        let transient = payload["transient"]?.boolValue
        return .data(.init(type: type, id: id, data: data, transient: transient))
      }
      return .raw(raw)
    }
  }

  private static func parseFinishReason(_ value: JSONValue?) -> FinishReason? {
    guard let raw = value?.stringValue else { return nil }
    return FinishReason(rawValue: raw) ?? .other
  }

  private static func decodeCodable<T: Decodable>(_ type: T.Type, from value: JSONValue?) -> T? {
    guard let value else { return nil }
    do {
      let data = try JSONEncoder().encode(value)
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      return nil
    }
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
}
