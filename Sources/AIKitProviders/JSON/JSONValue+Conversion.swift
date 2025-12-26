import Foundation

public extension JSONValue {
  static func from(_ value: Any) -> JSONValue? {
    switch value {
    case let dict as [String: Any]:
      var object: [String: JSONValue] = [:]
      for (key, val) in dict {
        if let converted = JSONValue.from(val) {
          object[key] = converted
        } else {
          return nil
        }
      }
      return .object(object)
    case let array as [Any]:
      var items: [JSONValue] = []
      items.reserveCapacity(array.count)
      for item in array {
        guard let converted = JSONValue.from(item) else { return nil }
        items.append(converted)
      }
      return .array(items)
    case let string as String:
      return .string(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return .bool(number.boolValue)
      }
      return .number(number.doubleValue)
    case _ as NSNull:
      return .null
    default:
      return nil
    }
  }
}

