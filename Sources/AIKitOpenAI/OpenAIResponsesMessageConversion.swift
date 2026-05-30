import Foundation
import AIKitProviders

struct OpenAIResponsesInput {
  var instructions: String?
  var items: [JSONValue]
}

func convertToOpenAIResponsesInput(
  _ messages: [ModelMessage],
  systemMessageMode: OpenAISystemMessageMode = .system
) throws -> OpenAIResponsesInput {
  var instructionParts: [String] = []
  var items: [JSONValue] = []

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
        items.append(messageItem(role: "developer", content: [.object(["type": .string("input_text"), "text": .string(contentText)])]))
      case .system:
        instructionParts.append(contentText)
      }
    case .user:
      var contentParts: [JSONValue] = []
      for part in message.content {
        switch part {
        case .text(let textPart):
          contentParts.append(.object(["type": .string("input_text"), "text": .string(textPart.text)]))
        case .image(let image):
          let mediaType = image.mediaType ?? "image/jpeg"
          let fileUrl = getFileUrl(part: image.data, mediaType: mediaType, defaultMediaType: "image/jpeg")
          contentParts.append(.object(["type": .string("input_image"), "image_url": .string(fileUrl)]))
        case .file(let file):
          let mediaType = file.mediaType ?? "application/pdf"
          let fileUrl = getFileUrl(part: file.data, mediaType: mediaType, defaultMediaType: "application/pdf")
          var fileObject: [String: JSONValue] = ["type": .string("input_file")]
          if isURLString(fileUrl, protocols: ["http", "https"]) {
            fileObject["file_url"] = .string(fileUrl)
          } else {
            fileObject["file_data"] = .string(fileUrl)
            fileObject["filename"] = .string(file.filename ?? "file")
          }
          contentParts.append(.object(fileObject))
        default:
          continue
        }
      }
      items.append(messageItem(role: "user", content: contentParts))
    case .assistant:
      var contentParts: [JSONValue] = []
      var toolCallItems: [JSONValue] = []
      for part in message.content {
        switch part {
        case .text(let textPart):
          contentParts.append(.object(["type": .string("output_text"), "text": .string(textPart.text)]))
        case .toolCall(let call):
          let arguments = call.inputJSON.isEmpty
            ? (OpenAIJSON.jsonString(from: call.input ?? .object([:])) ?? "{}")
            : call.inputJSON
          toolCallItems.append(.object([
            "type": .string("function_call"),
            "call_id": .string(call.toolCallID),
            "name": .string(call.toolName),
            "arguments": .string(arguments),
          ]))
        default:
          continue
        }
      }
      if contentParts.isEmpty == false {
        items.append(messageItem(role: "assistant", content: contentParts))
      }
      items.append(contentsOf: toolCallItems)
    case .tool:
      for part in message.content {
        guard let item = toolResultItem(part) else { continue }
        items.append(item)
      }
    }
  }

  return OpenAIResponsesInput(
    instructions: instructionParts.isEmpty ? nil : instructionParts.joined(separator: "\n\n"),
    items: items
  )
}

private func messageItem(role: String, content: [JSONValue]) -> JSONValue {
  .object([
    "type": .string("message"),
    "role": .string(role),
    "content": .array(content),
  ])
}

private func toolResultItem(_ part: ModelMessagePart) -> JSONValue? {
  switch part {
  case .toolResult(let result):
    return .object([
      "type": .string("function_call_output"),
      "call_id": .string(result.toolCallID),
      "output": .string(OpenAIJSON.jsonString(from: result.output) ?? ""),
    ])
  case .toolError(let error):
    return .object([
      "type": .string("function_call_output"),
      "call_id": .string(error.toolCallID),
      "output": .string(error.error),
    ])
  case .toolOutputDenied(let denied):
    return .object([
      "type": .string("function_call_output"),
      "call_id": .string(denied.toolCallID),
      "output": .string("Tool execution denied"),
    ])
  default:
    return nil
  }
}
