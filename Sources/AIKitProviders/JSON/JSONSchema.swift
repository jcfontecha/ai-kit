import Foundation

public struct JSONSchema: Sendable, Codable, Equatable {
  public var value: [String: JSONValue]

  public init(_ value: [String: JSONValue]) {
    self.value = value
  }
}

