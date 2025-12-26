import Foundation

public enum JSONValue: Sendable, Codable, Equatable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
      return
    }
    if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
      return
    }
    if let string = try? container.decode(String.self) {
      self = .string(string)
      return
    }
    if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
      return
    }
    if let number = try? container.decode(Double.self) {
      self = .number(number)
      return
    }
    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

