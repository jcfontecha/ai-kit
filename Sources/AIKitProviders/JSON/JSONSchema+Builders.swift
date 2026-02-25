import Foundation

public extension JSONSchema {
  func withoutSchemaURI() -> JSONSchema {
    var schema = value
    schema.removeValue(forKey: "$schema")
    return .init(schema)
  }

  func withDescription(_ description: String?) -> JSONSchema {
    guard let description else { return self }
    var schema = value
    schema["description"] = .string(description)
    return .init(schema)
  }

  static func object(
    properties: [String: JSONSchema],
    required: [String] = [],
    additionalProperties: Bool = false,
    includeSchemaURI: Bool = true,
    description: String? = nil
  ) -> JSONSchema {
    var propsObject: [String: JSONValue] = [:]
    for (k, v) in properties {
      propsObject[k] = .object(v.withoutSchemaURI().value)
    }

    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(propsObject),
      "additionalProperties": .bool(additionalProperties),
    ]

    if includeSchemaURI {
      schema["$schema"] = .string("http://json-schema.org/draft-07/schema#")
    }
    if !required.isEmpty { schema["required"] = .array(required.map(JSONValue.string)) }
    if let description { schema["description"] = .string(description) }

    return .init(schema)
  }

  static func array(
    items: JSONSchema,
    minItems: Int? = nil,
    maxItems: Int? = nil,
    uniqueItems: Bool? = nil,
    description: String? = nil
  ) -> JSONSchema {
    var schema: [String: JSONValue] = [
      "type": .string("array"),
      "items": .object(items.withoutSchemaURI().value),
    ]
    if let minItems { schema["minItems"] = .number(Double(minItems)) }
    if let maxItems { schema["maxItems"] = .number(Double(maxItems)) }
    if let uniqueItems { schema["uniqueItems"] = .bool(uniqueItems) }
    if let description { schema["description"] = .string(description) }
    return .init(schema)
  }

  static func string(
    description: String? = nil,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    pattern: String? = nil,
    format: String? = nil,
    enum values: [String]? = nil
  ) -> JSONSchema {
    var schema: [String: JSONValue] = ["type": .string("string")]
    if let description { schema["description"] = .string(description) }
    if let minLength { schema["minLength"] = .number(Double(minLength)) }
    if let maxLength { schema["maxLength"] = .number(Double(maxLength)) }
    if let pattern { schema["pattern"] = .string(pattern) }
    if let format { schema["format"] = .string(format) }
    if let values { schema["enum"] = .array(values.map(JSONValue.string)) }
    return .init(schema)
  }

  static func integer(
    description: String? = nil,
    minimum: Int? = nil,
    maximum: Int? = nil
  ) -> JSONSchema {
    var schema: [String: JSONValue] = ["type": .string("integer")]
    if let description { schema["description"] = .string(description) }
    if let minimum { schema["minimum"] = .number(Double(minimum)) }
    if let maximum { schema["maximum"] = .number(Double(maximum)) }
    return .init(schema)
  }

  static func number(
    description: String? = nil,
    minimum: Double? = nil,
    maximum: Double? = nil
  ) -> JSONSchema {
    var schema: [String: JSONValue] = ["type": .string("number")]
    if let description { schema["description"] = .string(description) }
    if let minimum { schema["minimum"] = .number(minimum) }
    if let maximum { schema["maximum"] = .number(maximum) }
    return .init(schema)
  }

  static func boolean(description: String? = nil) -> JSONSchema {
    var schema: [String: JSONValue] = ["type": .string("boolean")]
    if let description { schema["description"] = .string(description) }
    return .init(schema)
  }
}
