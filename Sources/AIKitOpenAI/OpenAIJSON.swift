import Foundation
import AIKitProviders

enum OpenAIJSON {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return encoder
  }()

  static let decoder = JSONDecoder()

  static func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
    guard let data = try? encoder.encode(value) else { return nil }
    return try? decoder.decode(JSONValue.self, from: data)
  }

  static func encodeToData(_ value: JSONValue) throws -> Data {
    try encoder.encode(value)
  }

  static func decodeJSONValue<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
    guard let data = try? encoder.encode(value) else { return nil }
    return try? decoder.decode(T.self, from: data)
  }

  static func isParsableJSON(_ input: String) -> Bool {
    guard let data = input.data(using: .utf8) else { return false }
    return (try? JSONSerialization.jsonObject(with: data)) != nil
  }

  static func jsonString(from value: JSONValue) -> String? {
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
