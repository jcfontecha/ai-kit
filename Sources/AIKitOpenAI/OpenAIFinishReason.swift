import Foundation
import AIKitProviders

func mapOpenAIFinishReason(_ value: String?) -> FinishReason {
  switch value {
  case "stop":
    return .stop
  case "length":
    return .length
  case "content_filter":
    return .contentFilter
  case "function_call", "tool_calls":
    return .toolCalls
  case nil:
    return .other
  default:
    return .other
  }
}
