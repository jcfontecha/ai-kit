import Foundation
import AIKitProviders

enum ReasoningPruneMode: Sendable, Equatable {
  case all
  case beforeLastMessage
}

enum ToolCallsPruneMode: Sendable, Equatable {
  case all
  case beforeLastMessage
  case beforeLast2Messages
}

struct ToolCallsPruneSetting: Sendable, Equatable {
  var mode: ToolCallsPruneMode
  var tools: [String]

  init(mode: ToolCallsPruneMode, tools: [String]) {
    self.mode = mode
    self.tools = tools
  }
}

enum ToolCallsPrune: Sendable, Equatable {
  case mode(ToolCallsPruneMode)
  case settings([ToolCallsPruneSetting])
}

struct PruneMessagesOptions: Sendable, Equatable {
  var messages: [ModelMessage]
  var reasoning: ReasoningPruneMode?
  var toolCalls: ToolCallsPrune?

  init(
    messages: [ModelMessage],
    reasoning: ReasoningPruneMode? = nil,
    toolCalls: ToolCallsPrune? = nil
  ) {
    self.messages = messages
    self.reasoning = reasoning
    self.toolCalls = toolCalls
  }
}

func pruneMessages(_ options: PruneMessagesOptions) -> [ModelMessage] {
  var messages = options.messages

  if let reasoning = options.reasoning {
    messages = pruneReasoning(messages: messages, mode: reasoning)
  }

  if let toolCalls = options.toolCalls {
    switch toolCalls {
    case .mode(let mode):
      messages = pruneToolCalls(messages: messages, mode: mode, tools: nil)
    case .settings(let settings):
      for setting in settings {
        messages = pruneToolCalls(messages: messages, mode: setting.mode, tools: Set(setting.tools))
      }
    }
  }

  return messages
}

private func pruneReasoning(messages: [ModelMessage], mode: ReasoningPruneMode) -> [ModelMessage] {
  let lastIndex = messages.indices.last ?? -1
  return messages.enumerated().compactMap { index, message in
    let keepReasoning: Bool
    switch mode {
    case .all:
      keepReasoning = false
    case .beforeLastMessage:
      keepReasoning = (index == lastIndex)
    }
    let newContent = message.content.filter { part in
      if case .reasoning(_) = part { return keepReasoning }
      return true
    }
    return newContent.isEmpty ? nil : ModelMessage(
      role: message.role,
      content: newContent,
      providerOptions: message.providerOptions,
      providerMetadata: message.providerMetadata
    )
  }
}

private func pruneToolCalls(
  messages: [ModelMessage],
  mode: ToolCallsPruneMode,
  tools: Set<String>?
) -> [ModelMessage] {
  let lastIndex = messages.indices.last ?? -1
  let lastTwoStart = max(0, lastIndex - 1)

  let toolCallNameByID = buildToolCallNameMap(messages: messages)
  let approvalToToolCallID = buildApprovalMap(messages: messages)

  let keptToolCallIDs: Set<String>
  if mode == .beforeLast2Messages {
    keptToolCallIDs = toolCallIDsInRange(
      messages: messages,
      range: lastTwoStart...lastIndex,
      tools: tools,
      toolCallNameByID: toolCallNameByID,
      approvalToToolCallID: approvalToToolCallID
    )
  } else {
    keptToolCallIDs = []
  }

  return messages.enumerated().compactMap { index, message in
    let newContent = message.content.filter { part in
      guard let info = toolPartInfo(
        part: part,
        toolCallNameByID: toolCallNameByID,
        approvalToToolCallID: approvalToToolCallID
      ) else {
        return true
      }

      if let tools, let name = info.toolName, !tools.contains(name) {
        return true
      }

      switch mode {
      case .all:
        return false
      case .beforeLastMessage:
        return index == lastIndex
      case .beforeLast2Messages:
        if index >= lastTwoStart {
          return true
        }
        if let toolCallID = info.toolCallID {
          return keptToolCallIDs.contains(toolCallID)
        }
        return false
      }
    }

    return newContent.isEmpty ? nil : ModelMessage(
      role: message.role,
      content: newContent,
      providerOptions: message.providerOptions,
      providerMetadata: message.providerMetadata
    )
  }
}

private struct ToolPartInfo {
  var toolCallID: String?
  var approvalID: String?
  var toolName: String?
}

private func toolPartInfo(
  part: ModelMessagePart,
  toolCallNameByID: [String: String],
  approvalToToolCallID: [String: String]
) -> ToolPartInfo? {
  switch part {
  case .toolCall(let call):
    return ToolPartInfo(toolCallID: call.toolCallID, approvalID: nil, toolName: call.toolName)
  case .toolResult(let result):
    return ToolPartInfo(toolCallID: result.toolCallID, approvalID: nil, toolName: result.toolName)
  case .toolError(let error):
    return ToolPartInfo(toolCallID: error.toolCallID, approvalID: nil, toolName: error.toolName)
  case .toolOutputDenied(let denied):
    return ToolPartInfo(toolCallID: denied.toolCallID, approvalID: nil, toolName: denied.toolName)
  case .toolApprovalRequest(let request):
    let name = toolCallNameByID[request.toolCallID]
    return ToolPartInfo(toolCallID: request.toolCallID, approvalID: request.approvalID, toolName: name)
  case .toolApprovalResponse(let response):
    let toolCallID = approvalToToolCallID[response.approvalID]
    let name = toolCallID.flatMap { toolCallNameByID[$0] }
    return ToolPartInfo(toolCallID: toolCallID, approvalID: response.approvalID, toolName: name)
  default:
    return nil
  }
}

private func buildToolCallNameMap(messages: [ModelMessage]) -> [String: String] {
  var map: [String: String] = [:]
  for message in messages {
    for part in message.content {
      if case let .toolCall(call) = part {
        map[call.toolCallID] = call.toolName
      }
      if case let .toolResult(result) = part {
        map[result.toolCallID] = result.toolName
      }
      if case let .toolError(error) = part {
        map[error.toolCallID] = error.toolName
      }
      if case let .toolOutputDenied(denied) = part {
        map[denied.toolCallID] = denied.toolName
      }
    }
  }
  return map
}

private func buildApprovalMap(messages: [ModelMessage]) -> [String: String] {
  var map: [String: String] = [:]
  for message in messages {
    for part in message.content {
      if case let .toolApprovalRequest(request) = part {
        map[request.approvalID] = request.toolCallID
      }
    }
  }
  return map
}

private func toolCallIDsInRange(
  messages: [ModelMessage],
  range: ClosedRange<Int>,
  tools: Set<String>?,
  toolCallNameByID: [String: String],
  approvalToToolCallID: [String: String]
) -> Set<String> {
  var ids: Set<String> = []
  for (idx, message) in messages.enumerated() where range.contains(idx) {
    for part in message.content {
      guard let info = toolPartInfo(
        part: part,
        toolCallNameByID: toolCallNameByID,
        approvalToToolCallID: approvalToToolCallID
      ) else { continue }

      if let tools, let name = info.toolName, !tools.contains(name) { continue }
      if let toolCallID = info.toolCallID {
        ids.insert(toolCallID)
      }
    }
  }
  return ids
}
