import Foundation

public enum FinishReason: String, Sendable, Codable {
  case stop
  case length
  case contentFilter = "content-filter"
  case toolCalls = "tool-calls"
  case error
  case other
}

