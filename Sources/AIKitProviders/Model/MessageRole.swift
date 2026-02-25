import Foundation

public enum MessageRole: String, Sendable, Codable, Equatable {
  case system
  case user
  case assistant
  case tool
}

