import Foundation
import AIKitProviders

struct PreparedAgentCall: Sendable {
  var message: String
  var extraSystemPrompt: String?
  var attachments: [JSONValue]

  func requestBody(runId: String, sessionKey: String, agentId: String?) -> [String: JSONValue] {
    params(runId: runId, sessionKey: sessionKey, agentId: agentId)
  }

  func params(runId: String, sessionKey: String, agentId: String?) -> [String: JSONValue] {
    var obj: [String: JSONValue] = [
      "idempotencyKey": .string(runId),
      "sessionKey": .string(sessionKey),
      "message": .string(message),
      "deliver": .bool(false),
    ]
    if let agentId {
      obj["agentId"] = .string(agentId)
    }
    if let extraSystemPrompt, extraSystemPrompt.isEmpty == false {
      obj["extraSystemPrompt"] = .string(extraSystemPrompt)
    }
    if attachments.isEmpty == false {
      obj["attachments"] = .array(attachments)
    }
    return obj
  }
}

func prepareAgentCall(from request: ModelRequest) throws -> PreparedAgentCall {
  let systemText = request.messages
    .filter { $0.role == .system }
    .flatMap { $0.content }
    .compactMap { part -> String? in
      if case .text(let text) = part { return text.text }
      return nil
    }
    .joined(separator: "\n\n")

  guard let userMessage = request.messages.last(where: { $0.role == .user }) else {
    throw OpenClawGatewayError.invalidConfiguration("OpenClaw requires a user message.")
  }

  var messageTextParts: [String] = []
  var attachments: [JSONValue] = []

  for part in userMessage.content {
    switch part {
    case .text(let text):
      messageTextParts.append(text.text)
    case .image(let image):
      attachments.append(try openClawAttachment(from: image))
    case .file(let file):
      attachments.append(try openClawAttachment(from: file))
    default:
      continue
    }
  }

  let message = messageTextParts.joined()
  if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty {
    throw OpenClawGatewayError.invalidConfiguration("OpenClaw requires a non-empty user message or attachment.")
  }

  return PreparedAgentCall(
    message: message,
    extraSystemPrompt: systemText.isEmpty ? nil : systemText,
    attachments: attachments
  )
}

private func openClawAttachment(from image: ImageContent) throws -> JSONValue {
  let base64 = try base64String(from: image.data)
  var obj: [String: JSONValue] = [
    "type": .string("image"),
    "content": .string(base64),
  ]
  if let mediaType = image.mediaType {
    obj["mimeType"] = .string(mediaType)
  }
  return .object(obj)
}

private func openClawAttachment(from file: FileContent) throws -> JSONValue {
  let base64 = try base64String(from: file.data)
  var obj: [String: JSONValue] = [
    "type": .string("file"),
    "content": .string(base64),
  ]
  if let mediaType = file.mediaType {
    obj["mimeType"] = .string(mediaType)
  }
  if let filename = file.filename {
    obj["fileName"] = .string(filename)
  }
  return .object(obj)
}

private func base64String(from content: DataContent) throws -> String {
  switch content {
  case .data(let data):
    return data.base64EncodedString()
  case .base64(let base64):
    return base64
  case .url:
    throw OpenClawGatewayError.invalidConfiguration("OpenClaw attachments do not support URL inputs. Provide Data or base64.")
  }
}

