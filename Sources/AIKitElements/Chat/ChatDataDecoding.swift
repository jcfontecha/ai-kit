import AIKit

/// Small read helpers over ``JSONValue`` for decoding ``ChatDataPart`` payloads.
extension JSONValue {
  var stringValue: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  var boolValue: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  var arrayValue: [JSONValue]? {
    if case .array(let value) = self { return value }
    return nil
  }

  subscript(key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  /// The element array, whether `self` is an array or an object wrapping `key`.
  func items(_ key: String) -> [JSONValue] {
    if let array = arrayValue { return array }
    return self[key]?.arrayValue ?? []
  }
}

extension ChatStepStatus {
  /// Decodes a status from its raw string; defaults to `.pending` when absent/unknown.
  init(jsonValue: JSONValue?) {
    self = jsonValue?.stringValue.flatMap(ChatStepStatus.init(rawValue:)) ?? .pending
  }
}
