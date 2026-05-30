import Foundation
import AIKitProviders

func convertToOpenAIChatMessages(
  _ messages: [ModelMessage],
  systemMessageMode: OpenAISystemMessageMode = .system
) throws -> [OpenAIChatMessage] {
  var result: [OpenAIChatMessage] = []

  for message in messages {
    switch message.role {
    case .system:
      let contentText = message.content.compactMap { part -> String? in
        if case let .text(textPart) = part { return textPart.text }
        return nil
      }.joined()
      switch systemMessageMode {
      case .remove:
        continue
      case .developer:
        result.append(
          OpenAIChatMessage(role: "developer", content: .string(contentText), toolCalls: nil, toolCallID: nil)
        )
      case .system:
        result.append(
          OpenAIChatMessage(role: "system", content: .string(contentText), toolCalls: nil, toolCallID: nil)
        )
      }
    case .user:
      let textParts = message.content.compactMap { part -> MessageTextPart? in
        if case let .text(textPart) = part { return textPart }
        return nil
      }
      if message.content.count == 1, let textPart = textParts.first {
        result.append(
          OpenAIChatMessage(role: "user", content: .string(textPart.text), toolCalls: nil, toolCallID: nil)
        )
        break
      }

      var contentParts: [OpenAIChatContentPart] = []
      for part in message.content {
        switch part {
        case .text(let textPart):
          contentParts.append(.text(textPart.text))
        case .image(let image):
          let mediaType = image.mediaType ?? "image/jpeg"
          let fileUrl = getFileUrl(part: image.data, mediaType: mediaType, defaultMediaType: "image/jpeg")
          contentParts.append(.imageURL(fileUrl))
        case .file(let file):
          if let mediaType = file.mediaType, mediaType.starts(with: "audio/") {
            let audio = try getInputAudioData(file: file)
            contentParts.append(.inputAudio(data: audio.data, format: audio.format))
            continue
          }

          if let mediaType = file.mediaType, mediaType.starts(with: "image/") {
            let fileUrl = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "image/jpeg")
            contentParts.append(.imageURL(fileUrl))
            continue
          }

          let fileName = file.filename ?? ""
          let mediaType = file.mediaType ?? "application/pdf"
          let fileUrl = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "application/pdf")
          contentParts.append(.file(filename: fileName, fileData: fileUrl))
        default:
          continue
        }
      }

      result.append(
        OpenAIChatMessage(role: "user", content: .parts(contentParts), toolCalls: nil, toolCallID: nil)
      )
    case .assistant:
      var text = ""
      var toolCalls: [OpenAIChatToolCall] = []

      for part in message.content {
        switch part {
        case .text(let textPart):
          text += textPart.text
        case .toolCall(let call):
          let arguments = call.inputJSON.isEmpty ? (OpenAIJSON.jsonString(from: call.input ?? .null) ?? "{}") : call.inputJSON
          toolCalls.append(
            OpenAIChatToolCall(
              type: "function",
              id: call.toolCallID,
              function: OpenAIChatToolCallFunction(name: call.toolName, arguments: arguments)
            )
          )
        default:
          continue
        }
      }

      let content: OpenAIChatMessageContent? = text.isEmpty ? nil : .string(text)

      result.append(
        OpenAIChatMessage(
          role: "assistant",
          content: content,
          toolCalls: toolCalls.isEmpty ? nil : toolCalls,
          toolCallID: nil
        )
      )
    case .tool:
      for part in message.content {
        guard let toolMessage = toolMessagePart(part) else {
          continue
        }
        result.append(toolMessage)
      }
    }
  }

  return result
}

private func toolMessagePart(_ part: ModelMessagePart) -> OpenAIChatMessage? {
  switch part {
  case .toolResult(let result):
    return OpenAIChatMessage(
      role: "tool",
      content: .string(OpenAIJSON.jsonString(from: result.output) ?? ""),
      toolCalls: nil,
      toolCallID: result.toolCallID
    )
  case .toolError(let error):
    return OpenAIChatMessage(
      role: "tool",
      content: .string(error.error),
      toolCalls: nil,
      toolCallID: error.toolCallID
    )
  case .toolOutputDenied(let denied):
    return OpenAIChatMessage(
      role: "tool",
      content: .string("Tool execution denied"),
      toolCalls: nil,
      toolCallID: denied.toolCallID
    )
  default:
    return nil
  }
}
