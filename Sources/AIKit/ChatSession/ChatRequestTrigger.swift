import Foundation

/// Mirrors the AI SDK UI transport `trigger` values used by `useChat` / `AbstractChat`.
///
/// Source of truth:
/// - `ai-sdk/packages/ai/src/ui/chat.ts`
/// - `ai-sdk/packages/ai/src/ui/http-chat-transport.ts`
public enum ChatRequestTrigger: String, Sendable, Codable, Equatable {
  case submitMessage = "submit-message"
  case regenerateMessage = "regenerate-message"
  case resumeStream = "resume-stream"
}

