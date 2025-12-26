import Foundation
import AIKitProviders

/// A minimal, Codable representation of the AI SDK UI `UIMessage` type.
///
/// Source of truth: `ai-sdk/packages/ai/src/ui/ui-messages.ts`.
public struct AIUIMessage: Sendable, Codable, Equatable {
  public var id: String
  public var role: String
  public var metadata: JSONValue?
  public var parts: [JSONValue]

  public init(
    id: String,
    role: String,
    metadata: JSONValue? = nil,
    parts: [JSONValue]
  ) {
    self.id = id
    self.role = role
    self.metadata = metadata
    self.parts = parts
  }
}

