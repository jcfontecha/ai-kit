import Foundation
import AIKitProviders

extension JSONValue {
  var stringValue: String? {
    if case let .string(value) = self { return value }
    return nil
  }

  var boolValue: Bool? {
    if case let .bool(value) = self { return value }
    return nil
  }

  var intValue: Int? {
    if case let .number(value) = self { return Int(value) }
    return nil
  }

  var objectValue: [String: JSONValue]? {
    if case let .object(obj) = self { return obj }
    return nil
  }

  var arrayValue: [JSONValue]? {
    if case let .array(arr) = self { return arr }
    return nil
  }
}

