import Foundation
import AIKitProviders

struct ToolApprovalResult: Sendable, Equatable {
  var approvalRequest: ToolApprovalRequest
  var approvalResponse: ToolApprovalResponse
  var toolCall: ToolCall

  init(
    approvalRequest: ToolApprovalRequest,
    approvalResponse: ToolApprovalResponse,
    toolCall: ToolCall
  ) {
    self.approvalRequest = approvalRequest
    self.approvalResponse = approvalResponse
    self.toolCall = toolCall
  }
}

struct ToolApprovalsCollection: Sendable, Equatable {
  var approvedToolApprovals: [ToolApprovalResult]
  var deniedToolApprovals: [ToolApprovalResult]

  init(
    approvedToolApprovals: [ToolApprovalResult] = [],
    deniedToolApprovals: [ToolApprovalResult] = []
  ) {
    self.approvedToolApprovals = approvedToolApprovals
    self.deniedToolApprovals = deniedToolApprovals
  }
}

struct ToolApprovalCollectionError: Error, Sendable, Equatable {
  var message: String
  init(_ message: String) { self.message = message }
}

func collectToolApprovals(messages: [ModelMessage]) throws -> ToolApprovalsCollection {
  guard let last = messages.last, last.role == .tool else {
    return .init()
  }

  guard let assistantIndex = messages.lastIndex(where: { $0.role == .assistant }) else {
    return .init()
  }

  let assistant = messages[assistantIndex]
  let toolMessage = last

  var toolCallsByID: [String: ToolCall] = [:]
  var approvalRequestsByID: [String: ToolApprovalRequest] = [:]

  for part in assistant.content {
    switch part {
    case .toolCall(let call):
      toolCallsByID[call.toolCallID] = call
    case .toolApprovalRequest(let request):
      approvalRequestsByID[request.approvalID] = request
    default:
      break
    }
  }

  var approvalResponses: [ToolApprovalResponse] = []
  var toolCallIDsWithResults: Set<String> = []

  for part in toolMessage.content {
    switch part {
    case .toolApprovalResponse(let response):
      approvalResponses.append(response)
    case .toolResult(let result):
      toolCallIDsWithResults.insert(result.toolCallID)
    case .toolError(let error):
      toolCallIDsWithResults.insert(error.toolCallID)
    case .toolOutputDenied(let denied):
      toolCallIDsWithResults.insert(denied.toolCallID)
    default:
      break
    }
  }

  if approvalResponses.isEmpty {
    return .init()
  }

  var approved: [ToolApprovalResult] = []
  var denied: [ToolApprovalResult] = []

  for response in approvalResponses {
    guard let request = approvalRequestsByID[response.approvalID] else {
      throw ToolApprovalCollectionError(
        "Tool approval response references unknown approvalId: \"\(response.approvalID)\""
      )
    }
    guard let toolCall = toolCallsByID[request.toolCallID] else {
      throw ToolApprovalCollectionError(
        "Tool call \"\(request.toolCallID)\" not found for approval request \"\(request.approvalID)\"."
      )
    }
    if toolCallIDsWithResults.contains(request.toolCallID) {
      continue
    }
    let bundle = ToolApprovalResult(
      approvalRequest: request,
      approvalResponse: response,
      toolCall: toolCall
    )
    if response.approved {
      approved.append(bundle)
    } else {
      denied.append(bundle)
    }
  }

  return .init(approvedToolApprovals: approved, deniedToolApprovals: denied)
}
