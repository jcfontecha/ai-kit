import Foundation
import AIKitProviders

struct ConvertToModelMessagesOptions: Sendable {
  var tools: ToolRegistry?
  var ignoreIncompleteToolCalls: Bool
  var convertDataPart: ChatDataPartConverter?

  init(
    tools: ToolRegistry? = nil,
    ignoreIncompleteToolCalls: Bool = false,
    convertDataPart: ChatDataPartConverter? = nil
  ) {
    self.tools = tools
    self.ignoreIncompleteToolCalls = ignoreIncompleteToolCalls
    self.convertDataPart = convertDataPart
  }
}

func convertToModelMessages(
  _ messages: [ChatMessage],
  options: ConvertToModelMessagesOptions
) async throws -> [ModelMessage] {
  let normalizedMessages: [ChatMessage]
  if options.ignoreIncompleteToolCalls {
    normalizedMessages = messages.map { message in
      var copy = message
      copy.parts = message.parts.filter { part in
        guard case let .tool(tool) = part else { return true }
        switch tool.state {
        case .inputStreaming, .inputAvailable:
          return false
        default:
          return true
        }
      }
      return copy
    }
  } else {
    normalizedMessages = messages
  }

  var modelMessages: [ModelMessage] = []
  modelMessages.reserveCapacity(normalizedMessages.count)

  for message in normalizedMessages {
    switch message.role {
    case .system:
      let textParts = message.parts.compactMap { part -> ChatTextPart? in
        guard case let .text(text) = part else { return nil }
        return text
      }
      let text = textParts.map(\.text).joined()

      var mergedMetadata: ProviderMetadata = [:]
      for part in textParts {
        if let metadata = part.providerMetadata {
          for (key, value) in metadata { mergedMetadata[key] = value }
        }
      }

      modelMessages.append(
        .init(
          role: .system,
          content: [.text(.init(text: text, providerOptions: providerOptions(from: mergedMetadata)))],
          providerOptions: providerOptions(from: mergedMetadata)
        )
      )

    case .user:
      var content: [ModelMessagePart] = []

      for part in message.parts {
        switch part {
        case .text(let textPart):
          content.append(
            .text(.init(text: textPart.text, providerOptions: providerOptions(from: textPart.providerMetadata)))
          )
        case .file(let filePart):
          content.append(
            .file(.init(
              data: filePart.data,
              filename: filePart.filename,
              mediaType: filePart.mediaType,
              providerOptions: providerOptions(from: filePart.providerMetadata)
            ))
          )
        case .reasoning:
          // Ignore reasoning in user messages.
          continue
        case .data(let dataPart):
          // Mirror `convertToModelMessages`: data parts are ignored unless a converter is provided.
          guard let convertDataPart = options.convertDataPart else { continue }
          guard let converted = convertDataPart(dataPart) else { continue }
          switch converted {
          case .text(let text): content.append(.text(text))
          case .file(let file): content.append(.file(file))
          }
        case .sourceURL, .sourceDocument:
          // Source parts are UI-only; they are not part of the model message content.
          continue
        case .tool, .stepStart:
          // Ignore tool/step parts in user messages.
          continue
        }
      }
      modelMessages.append(.init(role: .user, content: content))

    case .assistant:
      let blocks = assistantBlocks(from: message.parts)
      for block in blocks {
        let assistantContent = convertAssistantBlockToAssistantContent(block, convertDataPart: options.convertDataPart)
        if assistantContent.isEmpty == false {
          modelMessages.append(.init(role: .assistant, content: assistantContent))
        }

        let toolPartsForToolMessage = block.compactMap { part -> ChatToolPart? in
          guard case let .tool(tool) = part else { return nil }
          // Include non-provider-executed tools OR provider-executed tools with approval responses.
          if tool.providerExecuted == false { return tool }
          if case .approvalResponded = tool.state { return tool }
          return nil
        }

        let toolMessageParts = try await convertToolPartsToToolMessageContent(
          toolPartsForToolMessage,
          tools: options.tools
        )
        if toolMessageParts.isEmpty == false {
          modelMessages.append(.init(role: .tool, content: toolMessageParts))
        }
      }

    case .tool:
      // ChatMessage tool role is currently not part of the v0 UI model.
      throw AIKitError.invalidConfiguration("Unsupported ChatMessage role: tool")
    }
  }

  return modelMessages
}

private func assistantBlocks(from parts: [ChatMessagePart]) -> [[ChatMessagePart]] {
  var blocks: [[ChatMessagePart]] = []
  var current: [ChatMessagePart] = []

  for part in parts {
    if case .stepStart = part {
      if current.isEmpty == false {
        blocks.append(current)
        current = []
      }
      continue
    }
    current.append(part)
  }

  if current.isEmpty == false {
    blocks.append(current)
  }

  return blocks
}

private func convertAssistantBlockToAssistantContent(
  _ block: [ChatMessagePart],
  convertDataPart: ChatDataPartConverter?
) -> [ModelMessagePart] {
  var content: [ModelMessagePart] = []

  for part in block {
    switch part {
    case .text(let textPart):
      content.append(.text(.init(text: textPart.text, providerOptions: providerOptions(from: textPart.providerMetadata))))

    case .file(let filePart):
      content.append(
        .file(.init(
          data: filePart.data,
          filename: filePart.filename,
          mediaType: filePart.mediaType,
          providerOptions: providerOptions(from: filePart.providerMetadata)
        ))
      )

    case .reasoning(let reasoningPart):
      content.append(.reasoning(.init(text: reasoningPart.text, providerOptions: providerOptions(from: reasoningPart.providerMetadata))))

    case .tool(let toolPart):
      // Skip tool calls that are still streaming (behavior).
      guard toolPart.state != .inputStreaming else { continue }

      let input: JSONValue? = {
        switch toolPart.state {
        case .outputError:
          return toolPart.input ?? toolPart.rawInput
        default:
          return toolPart.input
        }
      }()

      let approvalID: String? = {
        if let approval = toolPart.approval {
          return approval.id
        }
        switch toolPart.state {
        case .approvalRequested(let approvalID):
          return approvalID
        case .approvalResponded(let approvalID, _, _):
          return approvalID
        case .outputDenied(let approvalID, _):
          return approvalID
        default:
          return nil
        }
      }()

      content.append(
        .toolCall(.init(
          toolCallID: toolPart.toolCallID,
          toolName: toolPart.toolName,
          inputJSON: "",
          input: input,
          providerExecuted: toolPart.providerExecuted ? true : nil,
          dynamic: toolPart.dynamic ? true : nil,
          title: toolPart.title,
          providerMetadata: toolPart.callProviderMetadata
        ))
      )

      if let approvalID {
        content.append(.toolApprovalRequest(.init(approvalID: approvalID, toolCallID: toolPart.toolCallID)))
      }

      // Provider-executed tool results (parity): include tool results in assistant content and do not add tool-role outputs.
      if toolPart.providerExecuted {
        switch toolPart.state {
        case .outputAvailable(let preliminary):
          if let output = toolPart.output, let modelOutput = toolModelOutput(from: output, errorText: nil) {
            content.append(
              .toolResult(.init(
                toolCallID: toolPart.toolCallID,
                toolName: toolPart.toolName,
                inputJSON: nil,
                input: toolPart.input,
                output: modelOutput,
                preliminary: preliminary ? true : nil,
                providerExecuted: true,
                dynamic: toolPart.dynamic ? true : nil,
                title: toolPart.title,
                providerMetadata: toolPart.callProviderMetadata
              ))
            )
          }
        case .outputError(let errorText):
          if let modelOutput = toolModelOutput(from: nil, errorText: errorText, errorMode: .json) {
            content.append(
              .toolResult(.init(
                toolCallID: toolPart.toolCallID,
                toolName: toolPart.toolName,
                inputJSON: nil,
                input: toolPart.input ?? toolPart.rawInput,
                output: modelOutput,
                preliminary: nil,
                providerExecuted: true,
                dynamic: toolPart.dynamic ? true : nil,
                title: toolPart.title,
                providerMetadata: toolPart.callProviderMetadata
              ))
            )
          }
        default:
          break
        }
      }

    case .data(let dataPart):
      // Data UI parts are ignored unless a converter is provided.
      guard let convertDataPart else { continue }
      guard let converted = convertDataPart(dataPart) else { continue }
      switch converted {
      case .text(let text):
        content.append(.text(text))
      case .file(let file):
        content.append(.file(file))
      }

    case .sourceURL, .sourceDocument:
      // Source parts are UI-only; they are not part of the model message content.
      continue

    case .stepStart:
      continue
    }
  }

  return content
}

private func convertToolPartsToToolMessageContent(
  _ toolParts: [ChatToolPart],
  tools: ToolRegistry?
) async throws -> [ModelMessagePart] {
  var content: [ModelMessagePart] = []

  for toolPart in toolParts {
    if let approval = toolPart.approval, let approved = approval.approved {
      content.append(.toolApprovalResponse(.init(approvalID: approval.id, approved: approved, reason: approval.reason)))
    } else if case let .approvalResponded(approvalID, approved, reason) = toolPart.state {
      content.append(.toolApprovalResponse(.init(approvalID: approvalID, approved: approved, reason: reason)))
    }

    // For provider-executed tools, the result is already in the assistant content. Skip tool-role output to avoid duplication.
    if toolPart.providerExecuted {
      continue
    }

    switch toolPart.state {
    case .outputDenied:
      let reason: String = {
        if let approval = toolPart.approval { return approval.reason ?? "Tool execution denied." }
        if case let .outputDenied(_, reason) = toolPart.state { return reason ?? "Tool execution denied." }
        return "Tool execution denied."
      }()

      if let modelOutput = toolModelOutput(from: nil, errorText: reason) {
        content.append(
          .toolResult(.init(
            toolCallID: toolPart.toolCallID,
            toolName: toolPart.toolName,
            inputJSON: nil,
            input: nil,
            output: modelOutput,
            preliminary: nil,
            providerExecuted: nil,
            dynamic: toolPart.dynamic ? true : nil,
            title: toolPart.title,
            providerMetadata: toolPart.callProviderMetadata
          ))
        )
      }

    case .outputError(let errorText):
      if let modelOutput = toolModelOutput(from: nil, errorText: errorText) {
        content.append(
          .toolResult(.init(
            toolCallID: toolPart.toolCallID,
            toolName: toolPart.toolName,
            inputJSON: nil,
            input: nil,
            output: modelOutput,
            preliminary: nil,
            providerExecuted: toolPart.providerExecuted ? true : nil,
            dynamic: toolPart.dynamic ? true : nil,
            title: toolPart.title,
            providerMetadata: toolPart.callProviderMetadata
          ))
        )
      }

    case .outputAvailable(let preliminary):
      if let output = toolPart.output, let modelOutput = toolModelOutput(from: output, errorText: nil) {
        content.append(
          .toolResult(.init(
            toolCallID: toolPart.toolCallID,
            toolName: toolPart.toolName,
            inputJSON: nil,
            input: nil,
            output: modelOutput,
            preliminary: preliminary ? true : nil,
            providerExecuted: toolPart.providerExecuted ? true : nil,
            dynamic: toolPart.dynamic ? true : nil,
            title: toolPart.title,
            providerMetadata: toolPart.callProviderMetadata
          ))
        )
      }

    default:
      break
    }
  }

  return content
}

private enum ToolModelErrorMode {
  case text
  case json
}

private func toolModelOutput(from output: JSONValue?, errorText: String?, errorMode: ToolModelErrorMode = .text) -> JSONValue? {
  if let errorText {
    let type: String = switch errorMode {
    case .text: "error-text"
    case .json: "error-json"
    }
    return .object(["type": .string(type), "value": .string(errorText)])
  }

  guard let output else { return nil }

  switch output {
  case .string(let value):
    return .object(["type": .string("text"), "value": .string(value)])
  default:
    return .object(["type": .string("json"), "value": output])
  }
}

private func providerOptions(from metadata: ProviderMetadata?) -> ProviderOptions? {
  guard let metadata else { return nil }
  var options: ProviderOptions = [:]
  for (key, value) in metadata {
    if case let .object(object) = value {
      options[key] = object
    }
  }
  return options.isEmpty ? nil : options
}
