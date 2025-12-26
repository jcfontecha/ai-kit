import Foundation

public struct ToolApprovalRequest: Sendable, Equatable {
  public var approvalID: String
  public var toolCallID: String
  public var toolCall: ToolCall?

  public init(approvalID: String, toolCallID: String, toolCall: ToolCall? = nil) {
    self.approvalID = approvalID
    self.toolCallID = toolCallID
    self.toolCall = toolCall
  }
}

public struct ToolApprovalResponse: Sendable, Equatable {
  public var approvalID: String
  public var approved: Bool
  public var reason: String?

  public init(approvalID: String, approved: Bool, reason: String? = nil) {
    self.approvalID = approvalID
    self.approved = approved
    self.reason = reason
  }
}
