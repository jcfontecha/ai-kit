import Foundation
import AIKitProviders

public enum SystemPrompt: Sendable, Equatable {
  case text(String)
  /// Must have role `.system`.
  case message(ModelMessage)
  /// Must all have role `.system`.
  case messages([ModelMessage])

  public static func instructions(_ text: String) -> SystemPrompt { .text(text) }
}

