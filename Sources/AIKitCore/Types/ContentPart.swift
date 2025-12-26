import Foundation
import AIKitProviders

public enum ContentPart: Sendable, Equatable {
  case text(String, providerMetadata: ProviderMetadata? = nil)
  case reasoning(String, providerMetadata: ProviderMetadata? = nil)
  case toolCall(ToolCall)
  case toolResult(ToolResult)
  case toolError(ToolError)
  case toolOutputDenied(ToolOutputDenied)
  case toolApprovalRequest(ToolApprovalRequest)
  case toolApprovalResponse(ToolApprovalResponse)
  case source(Source)
  case file(GeneratedFile)
}
