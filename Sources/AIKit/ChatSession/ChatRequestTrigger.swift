import Foundation

/// Mirrors the UI transport `trigger` values used by `useChat` / `AbstractChat`.
public enum ChatRequestTrigger: String, Sendable, Codable, Equatable {
  case submitMessage = "submit-message"
  case regenerateMessage = "regenerate-message"
  case resumeStream = "resume-stream"
}
