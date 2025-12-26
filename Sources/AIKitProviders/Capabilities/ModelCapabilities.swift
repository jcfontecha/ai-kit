import Foundation

public struct ModelCapabilities: Sendable, OptionSet {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let toolCalling = Self(rawValue: 1 << 0)
  public static let toolInputStreaming = Self(rawValue: 1 << 1)
  public static let jsonSchemaOutput = Self(rawValue: 1 << 2)
  public static let reasoningParts = Self(rawValue: 1 << 3)
  public static let sources = Self(rawValue: 1 << 4)
}

