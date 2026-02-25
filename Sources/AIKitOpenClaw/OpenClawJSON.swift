import Foundation
import AIKitProviders

enum OpenClawJSON {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
  }()

  static let decoder = JSONDecoder()

  static func decode(_ text: String) throws -> JSONValue {
    guard let data = text.data(using: .utf8) else {
      throw OpenClawGatewayError.invalidJSON("Invalid UTF-8")
    }
    return try decoder.decode(JSONValue.self, from: data)
  }

  static func encodeToString(_ value: JSONValue) throws -> String {
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
      throw OpenClawGatewayError.invalidJSON("Unable to encode UTF-8")
    }
    return text
  }

  static func jsonString(from value: JSONValue) -> String? {
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

