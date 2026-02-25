import Foundation
import AIKitProviders

private struct AssistantTextMerge: Sendable {
  var text: String
  var delta: String
}

private func continuationSeparator(for current: String) -> String {
  guard current.isEmpty == false else { return "" }
  guard let last = current.last else { return "" }
  return last.isWhitespace ? "" : " "
}

private func mergeAssistantText(current: String, incoming: String) -> AssistantTextMerge {
  if incoming.hasPrefix(current) {
    let delta = String(incoming.dropFirst(current.count))
    return .init(text: incoming, delta: delta)
  }

  if current.hasPrefix(incoming) {
    return .init(text: incoming, delta: "")
  }

  // Treat non-prefix updates as a new assistant segment for the same run.
  // This avoids repeated phrase explosions when providers start a fresh
  // assistant message (for example, after tool execution) while still using
  // chat delta events.
  let separator = continuationSeparator(for: current)
  return .init(text: incoming, delta: separator + incoming)
}

actor OpenClawClientBox {
  private var client: OpenClawGatewayClient?

  func set(_ client: OpenClawGatewayClient?) {
    self.client = client
  }

  func close() async {
    await client?.close()
    client = nil
  }
}

struct OpenClawRunOutcome: Sendable {
  var finishReason: FinishReason
  var rawFinishReason: String?
  var usage: Usage
  var pendingToolCalls: [OpenClawPendingToolCall]
  var assistantText: String?
}

struct OpenClawPendingToolCall: Sendable {
  var id: String
  var name: String
  var argumentsJSON: String
  var input: JSONValue?
}

actor OpenClawStreamTracker {
  private var streamedToolCallIDs: Set<String> = []
  private var assistantText = ""

  func recordToolCallID(_ id: String) {
    guard id.isEmpty == false else { return }
    streamedToolCallIDs.insert(id)
  }

  func snapshotStreamedToolCallIDs() -> Set<String> {
    streamedToolCallIDs
  }

  func setAssistantText(_ text: String) {
    assistantText = text
  }

  func snapshotAssistantText() -> String {
    assistantText
  }
}

private func mapOpenClawStopReason(_ stopReason: String?) -> FinishReason {
  guard let raw = stopReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        raw.isEmpty == false
  else {
    return .other
  }
  switch raw {
  case "stop", "completed", "end":
    return .stop
  case "tool_calls", "tool-calls":
    return .toolCalls
  case "length", "max_tokens":
    return .length
  case "content_filter", "content-filter":
    return .contentFilter
  case "error", "failed":
    return .error
  default:
    return .other
  }
}

private func parseOpenClawUsage(_ json: JSONValue?) -> Usage {
  guard case let .object(obj) = json else { return .init() }
  let inputNoCache = obj["input"]?.intValue
  let outputTotal = obj["output"]?.intValue
  let cacheRead = obj["cacheRead"]?.intValue
  let cacheWrite = obj["cacheWrite"]?.intValue
  let explicitTotal = obj["total"]?.intValue

  let derivedInputTotal: Int? = {
    if let explicitTotal {
      return explicitTotal - (outputTotal ?? 0)
    }
    let hasAnyInput = inputNoCache != nil || cacheRead != nil || cacheWrite != nil
    guard hasAnyInput else { return nil }
    return (inputNoCache ?? 0) + (cacheRead ?? 0) + (cacheWrite ?? 0)
  }()

  return Usage(
    inputTokens: .init(
      total: derivedInputTotal,
      noCache: inputNoCache,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite
    ),
    outputTokens: .init(total: outputTotal)
  )
}

private func parseOpenClawPendingToolCalls(_ json: JSONValue?) -> [OpenClawPendingToolCall] {
  guard case let .array(items) = json else { return [] }
  return items.compactMap { item in
    guard case let .object(obj) = item else { return nil }
    guard let id = obj["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), id.isEmpty == false else {
      return nil
    }
    guard let name = obj["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), name.isEmpty == false else {
      return nil
    }
    guard let argumentsJSON = obj["arguments"]?.stringValue else { return nil }
    let parsedInput = try? OpenClawJSON.decode(argumentsJSON)
    return .init(id: id, name: name, argumentsJSON: argumentsJSON, input: parsedInput)
  }
}

private func parseOpenClawAssistantText(_ json: JSONValue?) -> String? {
  guard case let .array(items) = json else { return nil }
  let parts = items.compactMap { item -> String? in
    guard case let .object(obj) = item else { return nil }
    guard let text = obj["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }
    guard text.isEmpty == false else { return nil }
    return text
  }
  guard parts.isEmpty == false else { return nil }
  return parts.joined(separator: "\n\n")
}

func parseFinalRunOutcome(payload: JSONValue?) -> OpenClawRunOutcome {
  guard case let .object(root) = payload else {
    return .init(
      finishReason: .other,
      rawFinishReason: nil,
      usage: .init(),
      pendingToolCalls: [],
      assistantText: nil
    )
  }

  if root["status"]?.stringValue == "error" {
    return .init(
      finishReason: .error,
      rawFinishReason: root["summary"]?.stringValue,
      usage: .init(),
      pendingToolCalls: [],
      assistantText: nil
    )
  }

  let result = root["result"]?.objectValue
  let meta = result?["meta"]?.objectValue
  let stopReason = meta?["stopReason"]?.stringValue
  let pendingToolCalls = parseOpenClawPendingToolCalls(meta?["pendingToolCalls"])
  let usage = parseOpenClawUsage(meta?["agentMeta"]?.objectValue?["usage"])
  let assistantText = parseOpenClawAssistantText(result?["payloads"])
  var finishReason = mapOpenClawStopReason(stopReason)

  if finishReason == .other && pendingToolCalls.isEmpty == false {
    finishReason = .toolCalls
  }
  if finishReason == .other, meta?["aborted"]?.boolValue == true {
    finishReason = .other
  }

  return .init(
    finishReason: finishReason,
    rawFinishReason: stopReason,
    usage: usage,
    pendingToolCalls: pendingToolCalls,
    assistantText: assistantText
  )
}

func streamRunEvents(
  runId: String,
  textPartId: String,
  client: OpenClawGatewayClient,
  continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation,
  tracker: OpenClawStreamTracker
) async throws {
  var lastAssistantText = ""
  var hasAgentAssistantStream = false

  for try await evt in client.events {
    try Task.checkCancellation()
    guard let payload = evt.payload else { continue }

    switch evt.event {
    case "chat":
      guard let chat = ParsedChatPayload(payload), chat.runId == runId else { continue }
      // Prefer assistant deltas from `agent` events when available.
      // They include explicit delta semantics and avoid chat-level resets
      // producing duplicated text.
      if hasAgentAssistantStream {
        continue
      }

      if let text = chat.assistantText {
        let merge = mergeAssistantText(current: lastAssistantText, incoming: text)
        lastAssistantText = merge.text
        await tracker.setAssistantText(lastAssistantText)
        if merge.delta.isEmpty == false {
          continuation.yield(.textDelta(id: textPartId, text: merge.delta))
        }
      }

      switch chat.state {
      case "final":
        continue
      case "aborted":
        continue
      case "error":
        continue
      default:
        break
      }

    case "agent":
      guard let agent = ParsedAgentPayload(payload), agent.runId == runId else { continue }

      if agent.stream == "assistant" {
        hasAgentAssistantStream = true
        if let text = agent.assistantText {
          let merge = mergeAssistantText(current: lastAssistantText, incoming: text)
          lastAssistantText = merge.text
          await tracker.setAssistantText(lastAssistantText)
          if merge.delta.isEmpty == false {
            continuation.yield(.textDelta(id: textPartId, text: merge.delta))
          }
        } else if let delta = agent.assistantDelta, delta.isEmpty == false {
          lastAssistantText += delta
          await tracker.setAssistantText(lastAssistantText)
          continuation.yield(.textDelta(id: textPartId, text: delta))
        }
        continue
      }

      if agent.stream == "tool", let toolEvent = agent.toolEvent {
        if case .toolCall = toolEvent.streamPart {
          await tracker.recordToolCallID(toolEvent.toolCallID)
        }
        continuation.yield(toolEvent.streamPart)
      }

    default:
      continue
    }
  }
}

private struct ParsedChatPayload: Sendable {
  var runId: String
  var state: String
  var assistantText: String?
  var errorMessage: String?
  var stopReason: String?

  init?(_ json: JSONValue) {
    guard case let .object(obj) = json else { return nil }
    guard let runId = obj["runId"]?.stringValue else { return nil }
    self.runId = runId
    self.state = obj["state"]?.stringValue ?? ""
    self.stopReason = obj["stopReason"]?.stringValue
    self.errorMessage = obj["errorMessage"]?.stringValue
    self.assistantText = extractAssistantText(from: obj["message"])
  }
}

private struct ParsedAgentPayload: Sendable {
  var runId: String
  var stream: String
  var data: JSONValue

  init?(_ json: JSONValue) {
    guard case let .object(obj) = json else { return nil }
    guard let runId = obj["runId"]?.stringValue else { return nil }
    guard let stream = obj["stream"]?.stringValue else { return nil }
    guard let data = obj["data"] else { return nil }
    self.runId = runId
    self.stream = stream
    self.data = data
  }

  var toolEvent: ParsedToolEvent? {
    guard stream == "tool" else { return nil }
    return ParsedToolEvent(data)
  }

  var assistantText: String? {
    guard stream == "assistant" else { return nil }
    return data.objectValue?["text"]?.stringValue
  }

  var assistantDelta: String? {
    guard stream == "assistant" else { return nil }
    return data.objectValue?["delta"]?.stringValue
  }
}

private struct ParsedToolEvent: Sendable {
  var toolCallID: String
  var streamPart: ModelStreamPart

  init?(_ json: JSONValue) {
    guard case let .object(obj) = json else { return nil }
    guard let phase = obj["phase"]?.stringValue else { return nil }
    guard let toolCallID = obj["toolCallId"]?.stringValue else { return nil }
    self.toolCallID = toolCallID
    let toolName = obj["name"]?.stringValue ?? "tool"
    let title = obj["meta"]?.stringValue

    switch phase {
    case "start":
      let input = obj["args"]
      let inputJSON = input.flatMap(OpenClawJSON.jsonString(from:)) ?? ""
      let call = ToolCall(
        toolCallID: toolCallID,
        toolName: toolName,
        inputJSON: inputJSON,
        input: input,
        providerExecuted: true,
        dynamic: true,
        title: title,
        providerMetadata: ["openclaw": .object(["phase": .string("start")])]
      )
      self.streamPart = .toolCall(call)
    case "update":
      let output = obj["partialResult"] ?? .null
      let result = ToolResult(
        toolCallID: toolCallID,
        toolName: toolName,
        inputJSON: nil,
        input: nil,
        output: output,
        preliminary: true,
        providerExecuted: true,
        dynamic: true,
        title: title,
        providerMetadata: ["openclaw": .object(["phase": .string("update")])]
      )
      self.streamPart = .toolResult(result)
    case "result":
      let isError = obj["isError"]?.boolValue ?? false
      if isError {
        let errorText = obj["result"].flatMap(OpenClawJSON.jsonString(from:)) ?? "tool error"
        let toolError = ToolError(
          toolCallID: toolCallID,
          toolName: toolName,
          inputJSON: nil,
          input: nil,
          error: errorText,
          providerExecuted: true,
          dynamic: true,
          title: title,
          providerMetadata: ["openclaw": .object(["phase": .string("result")])]
        )
        self.streamPart = .toolError(toolError)
      } else {
        let output = obj["result"] ?? .null
        let result = ToolResult(
          toolCallID: toolCallID,
          toolName: toolName,
          inputJSON: nil,
          input: nil,
          output: output,
          preliminary: false,
          providerExecuted: true,
          dynamic: true,
          title: title,
          providerMetadata: ["openclaw": .object(["phase": .string("result")])]
        )
        self.streamPart = .toolResult(result)
      }
    default:
      return nil
    }
  }
}

private func extractAssistantText(from message: JSONValue?) -> String? {
  guard case let .object(obj) = message else { return nil }
  guard case let .array(content) = obj["content"] else { return nil }
  for item in content {
    guard case let .object(entry) = item else { continue }
    if entry["type"]?.stringValue == "text", let text = entry["text"]?.stringValue {
      return text
    }
  }
  return nil
}
