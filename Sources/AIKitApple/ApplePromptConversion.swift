import Foundation
import AIKitProviders

struct ApplePreparedPrompt: Sendable {
  var instructions: String?
  var prompt: String
}

func applePreparePrompt(
  from messages: [ModelMessage],
  toolChoiceInstruction: String?
) throws -> ApplePreparedPrompt {
  var instructionsChunks: [String] = []
  var turns: [String] = []

  for message in messages {
    let text = try appleText(from: message)
    if text.isEmpty {
      continue
    }

    switch message.role {
    case .system:
      instructionsChunks.append(text)
    case .user:
      turns.append("User:\n\(text)")
    case .assistant:
      turns.append("Assistant:\n\(text)")
    case .tool:
      turns.append("Tool:\n\(text)")
    }
  }

  let instructions = instructionsChunks.isEmpty ? nil : instructionsChunks.joined(separator: "\n\n")
  if turns.isEmpty {
    throw AIKitError.invalidConfiguration("Apple provider requires at least one non-system message.")
  }

  if turns.count == 1,
     messages.count == 1,
     messages.first?.role == .user,
     toolChoiceInstruction == nil,
     let text = turns.first?.replacingOccurrences(of: "User:\n", with: "") {
    return .init(instructions: instructions, prompt: text)
  }

  var prompt = turns.joined(separator: "\n\n")
  if prompt.hasSuffix("\nAssistant:") == false {
    prompt += "\n\nAssistant:"
  }
  if let toolChoiceInstruction {
    prompt += "\n\(toolChoiceInstruction)"
  }

  return .init(instructions: instructions, prompt: prompt)
}

func appleToolChoiceInstruction(_ toolChoice: ToolChoice, tools: [ToolDefinition]) -> String? {
  switch toolChoice {
  case .auto:
    return nil
  case .none:
    return "Do not call tools."
  case .required:
    return "You must call at least one tool before giving a final answer."
  case .tool(let name):
    if tools.contains(where: { $0.name == name }) {
      return "You must call the tool \"\(name)\" before giving a final answer."
    }
    return "Requested tool \"\(name)\" is unavailable."
  }
}

private func appleText(from message: ModelMessage) throws -> String {
  var parts: [String] = []
  for part in message.content {
    switch part {
    case .text(let text):
      parts.append(text.text)
    case .reasoning(let reasoning):
      parts.append(reasoning.text)
    case .toolCall(let call):
      let input = call.inputJSON.isEmpty ? (appleJSONString(from: call.input ?? .null) ?? "{}") : call.inputJSON
      parts.append("ToolCall(name: \(call.toolName), id: \(call.toolCallID), input: \(input))")
    case .toolResult(let result):
      let output = appleJSONString(from: result.output) ?? "null"
      parts.append("ToolResult(name: \(result.toolName), id: \(result.toolCallID), output: \(output))")
    case .toolError(let error):
      parts.append("ToolError(name: \(error.toolName), id: \(error.toolCallID), error: \(error.error))")
    case .toolOutputDenied(let denied):
      parts.append("ToolOutputDenied(name: \(denied.toolName), id: \(denied.toolCallID))")
    case .toolApprovalRequest(let request):
      parts.append("ToolApprovalRequest(id: \(request.approvalID), toolCallID: \(request.toolCallID))")
    case .toolApprovalResponse(let response):
      let reason = response.reason ?? ""
      parts.append("ToolApprovalResponse(id: \(response.approvalID), approved: \(response.approved), reason: \(reason))")
    case .image:
      throw AIKitError.invalidConfiguration("Apple provider currently supports text-only message parts.")
    case .file:
      throw AIKitError.invalidConfiguration("Apple provider currently supports text-only message parts.")
    }
  }
  return parts.joined(separator: "\n")
}
