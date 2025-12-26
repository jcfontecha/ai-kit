import Foundation

public enum ChatAutoSubmitPredicates {
  public static func lastAssistantMessageIsCompleteWithToolCalls(
    messages: [ChatMessage]
  ) -> Bool {
    guard let message = messages.last else { return false }
    guard message.role == .assistant else { return false }

    let lastStepStartIndex = message.parts.enumerated().reduce(into: -1) { acc, item in
      if case .stepStart = item.element { acc = item.offset }
    }

    let toolParts = message.parts
      .dropFirst(lastStepStartIndex + 1)
      .compactMap { part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }
      .filter { $0.providerExecuted == false }

    guard toolParts.isEmpty == false else { return false }

    return toolParts.allSatisfy { tool in
      switch tool.state {
      case .outputAvailable, .outputError:
        return true
      default:
        return false
      }
    }
  }

  public static func lastAssistantMessageIsCompleteWithApprovalResponses(
    messages: [ChatMessage]
  ) -> Bool {
    guard let message = messages.last else { return false }
    guard message.role == .assistant else { return false }

    let lastStepStartIndex = message.parts.enumerated().reduce(into: -1) { acc, item in
      if case .stepStart = item.element { acc = item.offset }
    }

    let toolParts = message.parts
      .dropFirst(lastStepStartIndex + 1)
      .compactMap { part -> ChatToolPart? in
        guard case let .tool(tool) = part else { return nil }
        return tool
      }
      .filter { $0.providerExecuted == false }

    let approvalResponsesCount = toolParts.reduce(into: 0) { acc, tool in
      if case .approvalResponded = tool.state { acc += 1 }
    }

    guard approvalResponsesCount > 0 else { return false }

    return toolParts.allSatisfy { tool in
      switch tool.state {
      case .outputAvailable, .outputError, .approvalResponded:
        return true
      default:
        return false
      }
    }
  }
}

