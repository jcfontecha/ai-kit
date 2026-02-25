import Foundation
import FoundationModels
import AIKitProviders

func appleGenerationSchema(from schema: JSONSchema, defaultName: String) throws -> GenerationSchema {
  let normalized = appleNormalizeSchemaValue(.object(schema.value), rootTitle: defaultName)
  let data = try JSONEncoder().encode(normalized)
  return try JSONDecoder().decode(GenerationSchema.self, from: data)
}

func appleNormalizeSchemaValue(_ value: JSONValue, rootTitle: String?) -> JSONValue {
  normalizeSchema(value, defaultTitle: rootTitle)
}

private func normalizeSchema(_ value: JSONValue, defaultTitle: String?) -> JSONValue {
  switch value {
  case .object(var object):
    for (key, child) in object {
      object[key] = normalizeSchema(child, defaultTitle: nil)
    }

    if case .string("object") = object["type"] {
      let properties: [String: JSONValue]
      if case let .object(existing)? = object["properties"] {
        properties = existing
      } else {
        properties = [:]
      }

      object["properties"] = .object(properties)

      if object["x-order"] == nil {
        object["x-order"] = .array(properties.keys.sorted().map(JSONValue.string))
      }
      if object["additionalProperties"] == nil {
        object["additionalProperties"] = .bool(false)
      }
    }

    if let defaultTitle, object["title"] == nil {
      object["title"] = .string(defaultTitle)
    }
    return .object(object)

  case .array(let items):
    return .array(items.map { normalizeSchema($0, defaultTitle: nil) })
  case .string, .number, .bool, .null:
    return value
  }
}

func appleJSONValue(from generatedContent: GeneratedContent) -> JSONValue {
  switch generatedContent.kind {
  case .null:
    return .null
  case .bool(let value):
    return .bool(value)
  case .number(let value):
    return .number(value)
  case .string(let value):
    return .string(value)
  case .array(let values):
    return .array(values.map(appleJSONValue(from:)))
  case .structure(let properties, _):
    var object: [String: JSONValue] = [:]
    for (key, value) in properties {
      object[key] = appleJSONValue(from: value)
    }
    return .object(object)
  @unknown default:
    return .null
  }
}

func appleGeneratedContent(from value: JSONValue) -> GeneratedContent {
  switch value {
  case .null:
    return .init(kind: .null, id: nil)
  case .bool(let value):
    return .init(kind: .bool(value), id: nil)
  case .number(let value):
    return .init(kind: .number(value), id: nil)
  case .string(let value):
    return .init(kind: .string(value), id: nil)
  case .array(let values):
    return .init(kind: .array(values.map(appleGeneratedContent(from:))), id: nil)
  case .object(let object):
    var properties: [String: GeneratedContent] = [:]
    properties.reserveCapacity(object.count)
    for (key, child) in object {
      properties[key] = appleGeneratedContent(from: child)
    }
    return .init(kind: .structure(properties: properties, orderedKeys: object.keys.sorted()), id: nil)
  }
}

func appleJSONString(from value: JSONValue) -> String? {
  guard let data = try? JSONEncoder().encode(value) else { return nil }
  return String(data: data, encoding: .utf8)
}
