import Foundation
import AIKitProviders

func convertToOpenRouterChatMessages(_ messages: [ModelMessage]) throws -> [OpenRouterChatMessage] {
  var result: [OpenRouterChatMessage] = []

  for message in messages {
    switch message.role {
    case .system:
      let contentText = message.content.compactMap { part -> String? in
        if case let .text(textPart) = part { return textPart.text }
        return nil
      }.joined()
      result.append(
        OpenRouterChatMessage(
          role: "system",
          content: .string(contentText),
          toolCalls: nil,
          toolCallID: nil,
          reasoning: nil,
          reasoningDetails: nil,
          annotations: nil,
          cacheControl: cacheControl(from: message.providerOptions)
        )
      )
    case .user:
      let messageCacheControl = cacheControl(from: message.providerOptions)
      let textParts = message.content.compactMap { part -> MessageTextPart? in
        if case let .text(textPart) = part { return textPart }
        return nil
      }
      if message.content.count == 1, let textPart = textParts.first {
        let partCacheControl = cacheControl(from: textPart.providerOptions) ?? messageCacheControl
        if let partCacheControl {
          result.append(
            OpenRouterChatMessage(
              role: "user",
              content: .parts([.text(textPart.text, cacheControl: partCacheControl)]),
              toolCalls: nil,
              toolCallID: nil,
              reasoning: nil,
              reasoningDetails: nil,
              annotations: nil,
              cacheControl: nil
            )
          )
        } else {
          result.append(
            OpenRouterChatMessage(
              role: "user",
              content: .string(textPart.text),
              toolCalls: nil,
              toolCallID: nil,
              reasoning: nil,
              reasoningDetails: nil,
              annotations: nil,
              cacheControl: nil
            )
          )
        }
        break
      }

      var contentParts: [OpenRouterChatContentPart] = []
      for part in message.content {
        switch part {
        case .text(let textPart):
          let partCache = cacheControl(from: textPart.providerOptions) ?? messageCacheControl
          contentParts.append(.text(textPart.text, cacheControl: partCache))
        case .image(let image):
          let partCache = cacheControl(from: image.providerOptions) ?? messageCacheControl
          let mediaType = image.mediaType ?? "image/jpeg"
          let fileUrl = getFileUrl(part: image.data, mediaType: mediaType, defaultMediaType: "image/jpeg")
          contentParts.append(.imageURL(fileUrl, cacheControl: partCache))
        case .file(let file):
          if let mediaType = file.mediaType, mediaType.starts(with: "audio/") {
            let partCache = cacheControl(from: file.providerOptions) ?? messageCacheControl
            let audio = try getInputAudioData(file: file)
            contentParts.append(.inputAudio(data: audio.data, format: audio.format, cacheControl: partCache))
            continue
          }

          if let mediaType = file.mediaType, mediaType.starts(with: "image/") {
            let partCache = cacheControl(from: file.providerOptions) ?? messageCacheControl
            let fileUrl = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "image/jpeg")
            contentParts.append(.imageURL(fileUrl, cacheControl: partCache))
            continue
          }

          let fileName = openRouterFilename(from: file.providerOptions) ?? file.filename ?? ""
          let mediaType = file.mediaType ?? "application/pdf"
          let fileUrl = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "application/pdf")
          if isURLString(fileUrl, protocols: ["http", "https"]) {
            contentParts.append(.file(filename: fileName, fileData: fileUrl, cacheControl: nil))
          } else {
            let partCache = cacheControl(from: file.providerOptions) ?? messageCacheControl
            contentParts.append(.file(filename: fileName, fileData: fileUrl, cacheControl: partCache))
          }
        default:
          continue
        }
      }

      result.append(
        OpenRouterChatMessage(
          role: "user",
          content: .parts(contentParts),
          toolCalls: nil,
          toolCallID: nil,
          reasoning: nil,
          reasoningDetails: nil,
          annotations: nil,
          cacheControl: nil
        )
      )
    case .assistant:
      var text = ""
      var reasoning = ""
      var toolCalls: [OpenRouterChatToolCall] = []
      var accumulatedReasoningDetails: [ReasoningDetailUnion] = []

      for part in message.content {
        switch part {
        case .text(let textPart):
          text += textPart.text
        case .reasoning(let reasoningPart):
          reasoning += reasoningPart.text
          if let details = openRouterReasoningDetails(from: reasoningPart.providerOptions) {
            accumulatedReasoningDetails.append(contentsOf: details)
          }
        case .toolCall(let call):
          if let details = openRouterReasoningDetails(from: providerOptions(from: call.providerMetadata)) {
            accumulatedReasoningDetails.append(contentsOf: details)
          }
          let arguments = call.inputJSON.isEmpty ? (OpenRouterJSON.jsonString(from: call.input ?? .null) ?? "{}") : call.inputJSON
          toolCalls.append(
            OpenRouterChatToolCall(
              type: "function",
              id: call.toolCallID,
              function: OpenRouterChatToolCallFunction(name: call.toolName, arguments: arguments)
            )
          )
        default:
          continue
        }
      }

      let messageOptions = openRouterProviderOptions(from: message.providerOptions)
      let messageReasoningDetails = messageOptions?.reasoningDetails
      let messageAnnotations = messageOptions?.annotations

      let finalReasoningDetails: [ReasoningDetailUnion]? = {
        if let details = messageReasoningDetails, details.isEmpty == false {
          return details
        }
        return accumulatedReasoningDetails.isEmpty ? nil : accumulatedReasoningDetails
      }()

      let content: OpenRouterChatMessageContent? = text.isEmpty ? nil : .string(text)

      result.append(
        OpenRouterChatMessage(
          role: "assistant",
          content: content,
          toolCalls: toolCalls.isEmpty ? nil : toolCalls,
          toolCallID: nil,
          reasoning: reasoning.isEmpty ? nil : reasoning,
          reasoningDetails: finalReasoningDetails,
          annotations: messageAnnotations,
          cacheControl: cacheControl(from: message.providerOptions)
        )
      )
    case .tool:
      for part in message.content {
        guard let toolMessage = try toolMessagePart(part, messageProviderOptions: message.providerOptions) else {
          continue
        }
        result.append(toolMessage)
      }
    }
  }

  return result
}

func convertToOpenRouterCompletionPrompt(
  messages: [ModelMessage],
  inputFormat: String = "prompt",
  user: String = "user",
  assistant: String = "assistant"
) throws -> String {
  if inputFormat == "prompt",
     messages.count == 1,
     let message = messages.first,
     message.role == .user,
     message.content.count == 1,
     case let .text(textPart) = message.content.first {
    return textPart.text
  }

  var text = ""
  var remaining = messages
  if let first = remaining.first, first.role == .system {
    let systemText = first.content.compactMap { part -> String? in
      if case let .text(textPart) = part { return textPart.text }
      return nil
    }.joined()
    text += "\(systemText)\n\n"
    remaining = Array(remaining.dropFirst())
  }

  for message in remaining {
    switch message.role {
    case .system:
      throw OpenRouterInvalidResponseError(message: "Unexpected system message in prompt: \(message.content)")
    case .user:
      let userMessage = try message.content.map { part -> String in
        switch part {
        case .text(let textPart):
          return textPart.text
        case .file:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "file attachments")
        case .image:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "file attachments")
        default:
          return ""
        }
      }.joined()
      text += "\(user):\n\(userMessage)\n\n"
    case .assistant:
      let assistantMessage = try message.content.map { part -> String in
        switch part {
        case .text(let textPart):
          return textPart.text
        case .toolCall:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "tool-call messages")
        case .toolResult:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "tool-result messages")
        case .toolError:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "tool-result messages")
        case .toolOutputDenied:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "tool-result messages")
        case .reasoning:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "reasoning messages")
        case .file, .image:
          throw OpenRouterUnsupportedFunctionalityError(functionality: "file attachments")
        default:
          return ""
        }
      }.joined()
      text += "\(assistant):\n\(assistantMessage)\n\n"
    case .tool:
      throw OpenRouterUnsupportedFunctionalityError(functionality: "tool messages")
    }
  }

  text += "\(assistant):\n"
  return text
}

private func toolMessagePart(
  _ part: ModelMessagePart,
  messageProviderOptions: ProviderOptions?
) throws -> OpenRouterChatMessage? {
  switch part {
  case .toolResult(let result):
    return OpenRouterChatMessage(
      role: "tool",
      content: .string(OpenRouterJSON.jsonString(from: result.output) ?? ""),
      toolCalls: nil,
      toolCallID: result.toolCallID,
      reasoning: nil,
      reasoningDetails: nil,
      annotations: nil,
      cacheControl: cacheControl(from: messageProviderOptions) ??
        cacheControl(from: providerOptions(from: result.providerMetadata))
    )
  case .toolError(let error):
    return OpenRouterChatMessage(
      role: "tool",
      content: .string(error.error),
      toolCalls: nil,
      toolCallID: error.toolCallID,
      reasoning: nil,
      reasoningDetails: nil,
      annotations: nil,
      cacheControl: cacheControl(from: messageProviderOptions) ??
        cacheControl(from: providerOptions(from: error.providerMetadata))
    )
  case .toolOutputDenied(let denied):
    return OpenRouterChatMessage(
      role: "tool",
      content: .string("Tool execution denied"),
      toolCalls: nil,
      toolCallID: denied.toolCallID,
      reasoning: nil,
      reasoningDetails: nil,
      annotations: nil,
      cacheControl: cacheControl(from: messageProviderOptions)
    )
  default:
    return nil
  }
}

private func cacheControl(from providerOptions: ProviderOptions?) -> OpenRouterCacheControl? {
  guard let providerOptions else { return nil }
  if let openrouter = providerOptions["openrouter"],
     let value = openrouter["cacheControl"] ?? openrouter["cache_control"],
     case let .object(object) = value,
     case let .string(type) = object["type"] {
    return OpenRouterCacheControl(type: type)
  }
  if let anthropic = providerOptions["anthropic"],
     let value = anthropic["cacheControl"] ?? anthropic["cache_control"],
     case let .object(object) = value,
     case let .string(type) = object["type"] {
    return OpenRouterCacheControl(type: type)
  }
  return nil
}

private struct OpenRouterProviderOptionsPayload {
  var reasoningDetails: [ReasoningDetailUnion]?
  var annotations: [OpenRouterAnnotation]?
}

private func openRouterProviderOptions(from providerOptions: ProviderOptions?) -> OpenRouterProviderOptionsPayload? {
  guard let providerOptions, let openrouter = providerOptions["openrouter"] else { return nil }
  var payload = OpenRouterProviderOptionsPayload()

  if let reasoningValue = openrouter["reasoning_details"] {
    if let parsed = OpenRouterJSON.decodeJSONValue(reasoningValue, as: LossyDecodingArray<ReasoningDetailUnion>.self) {
      payload.reasoningDetails = parsed.elements
    }
  }

  if let annotationsValue = openrouter["annotations"] {
    if let parsed = OpenRouterJSON.decodeJSONValue(annotationsValue, as: LossyDecodingArray<OpenRouterAnnotation>.self) {
      payload.annotations = parsed.elements
    }
  }

  if payload.reasoningDetails == nil && payload.annotations == nil {
    return nil
  }
  return payload
}

private func openRouterReasoningDetails(from providerOptions: ProviderOptions?) -> [ReasoningDetailUnion]? {
  openRouterProviderOptions(from: providerOptions)?.reasoningDetails
}

private func openRouterFilename(from providerOptions: ProviderOptions?) -> String? {
  guard let openrouter = providerOptions?["openrouter"],
        let value = openrouter["filename"],
        case let .string(filename) = value else {
    return nil
  }
  return filename
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
