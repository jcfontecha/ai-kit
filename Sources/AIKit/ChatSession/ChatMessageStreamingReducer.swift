import Foundation
import AIKitProviders

enum ChatMessageStreamingReducer {
  struct State: Sendable, Equatable {
    var partialToolInputs: [String: String] = [:]
    var pendingStepStart: Bool = false
  }

  static func apply(
    _ part: AIUIMessageStreamPart,
    messages: inout [ChatMessage],
    state: inout State,
    makeMessageID: () -> String = { UUID().uuidString }
  ) {
    switch part {
    case .abort, .raw, .error:
      // Request-level errors/cancellation are owned by ChatSession (status, callbacks, etc.)
      return

    case .start(let messageID, let messageMetadata):
      guard messageID != nil || messageMetadata != nil else { return }

      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      if let messageID {
        messages[messages.count - 1].id = messageID
      }
      if let messageMetadata {
        messages[messages.count - 1].metadata = mergeObjects(
          base: messages[messages.count - 1].metadata,
          overrides: messageMetadata
        )
      }
      return

    case .finish(_, let messageMetadata):
      if let messageMetadata {
        ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
        messages[messages.count - 1].metadata = mergeObjects(
          base: messages[messages.count - 1].metadata,
          overrides: messageMetadata
        )
      }
      return

    case .messageMetadata(let messageMetadata):
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      messages[messages.count - 1].metadata = mergeObjects(
        base: messages[messages.count - 1].metadata,
        overrides: messageMetadata
      )
      return

    case .finishStep:
      // If a step completes without any content parts, we still want the `stepStart` marker to exist.
      // This matches AI SDK `processUIMessageStream` semantics and prevents auto-submit predicates
      // from repeatedly re-submitting when the server responds with an empty step.
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      return

    case .startStep:
      state.pendingStepStart = true
      return

    case .textStart(let id, let providerMetadata):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      insertStepStartAfterToolIfNeeded(&messages)
      messages[messages.count - 1].parts.append(
        .text(.init(id: id, text: "", state: .streaming, providerMetadata: providerMetadata))
      )

    case .textDelta(let id, let delta, let providerMetadata):
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      guard let index = lastIndexOfTextPart(with: id, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .text(part) = messages[messages.count - 1].parts[index] else { return }
      if delta.isEmpty == false {
        part.text += delta
      }
      if let providerMetadata { part.providerMetadata = providerMetadata }
      messages[messages.count - 1].parts[index] = .text(part)

    case .textEnd(let id, let providerMetadata):
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      guard let index = lastIndexOfTextPart(with: id, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .text(part) = messages[messages.count - 1].parts[index] else { return }
      part.state = .done
      if let providerMetadata { part.providerMetadata = providerMetadata }
      messages[messages.count - 1].parts[index] = .text(part)

    case .reasoningStart(let id, let providerMetadata):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      insertStepStartAfterToolIfNeeded(&messages)
      messages[messages.count - 1].parts.append(
        .reasoning(.init(id: id, text: "", state: .streaming, providerMetadata: providerMetadata))
      )

    case .reasoningDelta(let id, let delta, let providerMetadata):
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      guard let index = lastIndexOfReasoningPart(with: id, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .reasoning(part) = messages[messages.count - 1].parts[index] else { return }
      if delta.isEmpty == false {
        part.text += delta
      }
      if let providerMetadata { part.providerMetadata = providerMetadata }
      messages[messages.count - 1].parts[index] = .reasoning(part)

    case .reasoningEnd(let id, let providerMetadata):
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      guard let index = lastIndexOfReasoningPart(with: id, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .reasoning(part) = messages[messages.count - 1].parts[index] else { return }
      part.state = .done
      if let providerMetadata { part.providerMetadata = providerMetadata }
      messages[messages.count - 1].parts[index] = .reasoning(part)

    case .toolInputStart(let start):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs[start.toolCallID] = ""
      messages[messages.count - 1].parts.append(
        .tool(.init(
          toolCallID: start.toolCallID,
          toolName: start.toolName,
          title: start.title,
          providerExecuted: start.providerExecuted ?? false,
          dynamic: start.dynamic ?? false,
          callProviderMetadata: start.providerMetadata,
          state: .inputStreaming
        ))
      )

    case .toolInputDelta(let delta):
      guard delta.inputTextDelta.isEmpty == false else { return }
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      guard let index = lastIndexOfToolPart(with: delta.toolCallID, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .tool(tool) = messages[messages.count - 1].parts[index] else { return }
      let updatedText = (state.partialToolInputs[delta.toolCallID] ?? "") + delta.inputTextDelta
      state.partialToolInputs[delta.toolCallID] = updatedText
      tool.input = OutputParsing.parsePartialJSONValue(updatedText)
      tool.state = .inputStreaming
      if let providerMetadata = delta.providerMetadata { tool.callProviderMetadata = providerMetadata }
      messages[messages.count - 1].parts[index] = .tool(tool)

    case .toolInputEnd(let toolCallID):
      state.partialToolInputs.removeValue(forKey: toolCallID)
      return

    case .toolInputAvailable(let available):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs.removeValue(forKey: available.toolCallID)
      upsertToolInputAvailable(from: available, messages: &messages)

    case .toolOutputAvailable(let available):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs.removeValue(forKey: available.toolCallID)
      upsertToolOutputAvailable(from: available, messages: &messages)

    case .toolInputError(let error):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs.removeValue(forKey: error.toolCallID)
      upsertToolInputError(from: error, messages: &messages)

    case .toolOutputError(let error):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs.removeValue(forKey: error.toolCallID)
      upsertToolOutputError(from: error, messages: &messages)

    case .toolOutputDenied(let toolCallID):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      state.partialToolInputs.removeValue(forKey: toolCallID)
      guard let index = lastIndexOfToolPart(with: toolCallID, in: messages[messages.count - 1].parts) else {
        return
      }
      guard case var .tool(tool) = messages[messages.count - 1].parts[index] else { return }
      let approvalID: String? = {
        switch tool.state {
        case .approvalResponded(let approvalID, let approved, _):
          return approved ? nil : approvalID
        case .approvalRequested(let approvalID):
          return approvalID
        default:
          return nil
        }
      }()
      let reason: String? = {
        if case let .approvalResponded(_, approved, reason) = tool.state, approved == false {
          return reason
        }
        return nil
      }()
      tool.state = .outputDenied(approvalID: approvalID, reason: reason)
      messages[messages.count - 1].parts[index] = .tool(tool)

    case .toolApprovalRequest(let approvalID, let toolCallID):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      guard let index = lastIndexOfToolPart(with: toolCallID, in: messages[messages.count - 1].parts) else {
        messages[messages.count - 1].parts.append(.tool(.init(
          toolCallID: toolCallID,
          toolName: "unknown",
          approval: .init(id: approvalID),
          state: .approvalRequested(approvalID: approvalID)
        )))
        return
      }
      guard case var .tool(tool) = messages[messages.count - 1].parts[index] else { return }
      tool.approval = .init(id: approvalID)
      tool.state = .approvalRequested(approvalID: approvalID)
      messages[messages.count - 1].parts[index] = .tool(tool)

    case .data(let chunk):
      // Mirrors AI SDK default `isDataUIMessageChunk` clause:
      // - transient chunks are surfaced via `onData` but not added to `message.parts`
      // - if `id` is present, update existing part by (type,id) match, else append
      if chunk.transient == true {
        return
      }

      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)

      if let id = chunk.id,
         let index = firstIndexOfDataPart(type: chunk.type, id: id, in: messages[messages.count - 1].parts),
         case var .data(existing) = messages[messages.count - 1].parts[index] {
        existing.data = chunk.data
        messages[messages.count - 1].parts[index] = .data(existing)
        return
      }

      messages[messages.count - 1].parts.append(.data(.init(type: chunk.type, id: chunk.id, data: chunk.data)))

    case .file(let file):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      if let url = URL(string: file.url) {
        // Match AI SDK behavior: file UI part does not include providerMetadata.
        messages[messages.count - 1].parts.append(.file(.init(data: .url(url), filename: nil, mediaType: file.mediaType)))
      }

    case .sourceURL(let source):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      messages[messages.count - 1].parts.append(
        .sourceURL(.init(sourceID: source.sourceID, url: source.url, title: source.title, providerMetadata: source.providerMetadata))
      )

    case .sourceDocument(let source):
      flushPendingStepStartIfNeeded(&messages, state: &state, makeMessageID: makeMessageID)
      ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
      insertImplicitStepStartIfNeeded(&messages, state: &state)
      messages[messages.count - 1].parts.append(
        .sourceDocument(.init(
          sourceID: source.sourceID,
          mediaType: source.mediaType,
          title: source.title,
          filename: source.filename,
          providerMetadata: source.providerMetadata
        ))
      )
    }
  }

  private static func mergeObjects(base: JSONValue?, overrides: JSONValue) -> JSONValue? {
    // Mirror AI SDK `mergeObjects`: deep-merge objects, replace arrays/primitives.
    guard case let .object(overridesObject) = overrides else { return overrides }

    guard let base else {
      return .object(overridesObject)
    }

    guard case let .object(baseObject) = base else {
      return .object(overridesObject)
    }

    var merged = baseObject
    for (key, overrideValue) in overridesObject {
      if case .object = overrideValue,
         case let .object(existingValue)? = merged[key],
         let deep = mergeObjects(base: .object(existingValue), overrides: overrideValue) {
        merged[key] = deep
        continue
      }
      merged[key] = overrideValue
    }

    return .object(merged)
  }

  private static func ensureLastAssistantMessage(
    _ messages: inout [ChatMessage],
    makeMessageID: () -> String
  ) {
    if messages.last?.role == .assistant { return }
    messages.append(.init(id: makeMessageID(), role: .assistant, parts: []))
  }

  private static func flushPendingStepStartIfNeeded(
    _ messages: inout [ChatMessage],
    state: inout State,
    makeMessageID: () -> String
  ) {
    guard state.pendingStepStart else { return }
    state.pendingStepStart = false
    ensureLastAssistantMessage(&messages, makeMessageID: makeMessageID)
    messages[messages.count - 1].parts.append(.stepStart)
  }

  private static func insertImplicitStepStartIfNeeded(
    _ messages: inout [ChatMessage],
    state: inout State
  ) {
    guard state.pendingStepStart == false else { return }
    guard let lastIndex = messages.indices.last else { return }
    guard messages[lastIndex].role == .assistant else { return }
    guard messages[lastIndex].parts.isEmpty else { return }
    messages[lastIndex].parts.append(.stepStart)
  }

  private static func insertStepStartAfterToolIfNeeded(
    _ messages: inout [ChatMessage]
  ) {
    guard let lastIndex = messages.indices.last else { return }
    guard messages[lastIndex].role == .assistant else { return }
    guard case .tool = messages[lastIndex].parts.last else { return }
    messages[lastIndex].parts.append(.stepStart)
  }

  private static func lastIndexOfTextPart(with id: String, in parts: [ChatMessagePart]) -> Int? {
    parts.lastIndex(where: { part in
      guard case let .text(text) = part else { return false }
      return text.id == id
    })
  }

  private static func lastIndexOfReasoningPart(with id: String, in parts: [ChatMessagePart]) -> Int? {
    parts.lastIndex(where: { part in
      guard case let .reasoning(reasoning) = part else { return false }
      return reasoning.id == id
    })
  }

  private static func lastIndexOfToolPart(with toolCallID: String, in parts: [ChatMessagePart]) -> Int? {
    parts.lastIndex(where: { part in
      guard case let .tool(tool) = part else { return false }
      return tool.toolCallID == toolCallID
    })
  }

  private static func firstIndexOfDataPart(type: String, id: String, in parts: [ChatMessagePart]) -> Int? {
    parts.firstIndex(where: { part in
      guard case let .data(data) = part else { return false }
      return data.type == type && data.id == id
    })
  }

  private static func upsertToolInputAvailable(from call: ToolInputAvailable, messages: inout [ChatMessage]) {
    let idx = lastIndexOfToolPart(with: call.toolCallID, in: messages[messages.count - 1].parts)

    let tool = ChatToolPart(
      toolCallID: call.toolCallID,
      toolName: call.toolName,
      title: call.title,
      providerExecuted: call.providerExecuted ?? false,
      dynamic: call.dynamic ?? false,
      input: call.input,
      rawInput: nil,
      output: nil,
      callProviderMetadata: call.providerMetadata,
      state: .inputAvailable
    )

    if let idx {
      messages[messages.count - 1].parts[idx] = .tool(tool)
    } else {
      messages[messages.count - 1].parts.append(.tool(tool))
    }
  }

  private static func upsertToolOutputAvailable(from result: ToolOutputAvailable, messages: inout [ChatMessage]) {
    guard let idx = lastIndexOfToolPart(with: result.toolCallID, in: messages[messages.count - 1].parts) else {
      messages[messages.count - 1].parts.append(
        .tool(.init(
          toolCallID: result.toolCallID,
          toolName: "unknown",
          providerExecuted: result.providerExecuted ?? false,
          dynamic: result.dynamic ?? false,
          output: result.output,
          state: .outputAvailable(preliminary: result.preliminary ?? false)
        ))
      )
      return
    }

    guard case var .tool(tool) = messages[messages.count - 1].parts[idx] else { return }
    tool.output = result.output
    tool.state = .outputAvailable(preliminary: result.preliminary ?? false)
    messages[messages.count - 1].parts[idx] = .tool(tool)
  }

  private static func upsertToolInputError(from error: ToolInputError, messages: inout [ChatMessage]) {
    let idx = lastIndexOfToolPart(with: error.toolCallID, in: messages[messages.count - 1].parts)

    if idx == nil {
      let isDynamic = error.dynamic ?? false
      messages[messages.count - 1].parts.append(
        .tool(.init(
          toolCallID: error.toolCallID,
          toolName: error.toolName,
          title: error.title,
          providerExecuted: error.providerExecuted ?? false,
          dynamic: isDynamic,
          input: isDynamic ? error.input : nil,
          rawInput: isDynamic ? nil : error.input,
          callProviderMetadata: error.providerMetadata,
          state: .outputError(errorText: error.errorText)
        ))
      )
      return
    }

    guard let idx, case var .tool(tool) = messages[messages.count - 1].parts[idx] else { return }
    if tool.toolName == "unknown" {
      tool.toolName = error.toolName
    }
    if let providerExecuted = error.providerExecuted {
      tool.providerExecuted = providerExecuted
    }
    if let dynamic = error.dynamic {
      tool.dynamic = dynamic
    }
    let isDynamic = error.dynamic ?? tool.dynamic
    tool.title = tool.title ?? error.title

    // Match AI SDK `processUIMessageStream` behavior:
    // - dynamic tool: `input` is preserved (rawInput is nil)
    // - static tool: `input` is cleared and `rawInput` is set to the raw input payload
    if isDynamic {
      tool.input = error.input
      tool.rawInput = nil
    } else {
      tool.input = nil
      tool.rawInput = error.input
    }

    tool.callProviderMetadata = tool.callProviderMetadata ?? error.providerMetadata
    tool.state = .outputError(errorText: error.errorText)
    messages[messages.count - 1].parts[idx] = .tool(tool)
  }

  private static func upsertToolOutputError(from error: ToolOutputError, messages: inout [ChatMessage]) {
    guard let idx = lastIndexOfToolPart(with: error.toolCallID, in: messages[messages.count - 1].parts) else {
      messages[messages.count - 1].parts.append(
        .tool(.init(
          toolCallID: error.toolCallID,
          toolName: "unknown",
          providerExecuted: error.providerExecuted ?? false,
          dynamic: error.dynamic ?? false,
          state: .outputError(errorText: error.errorText)
        ))
      )
      return
    }

    guard case var .tool(tool) = messages[messages.count - 1].parts[idx] else { return }
    tool.state = .outputError(errorText: error.errorText)
    messages[messages.count - 1].parts[idx] = .tool(tool)
  }
}
