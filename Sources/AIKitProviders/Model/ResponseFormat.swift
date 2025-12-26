import Foundation

public enum ResponseFormat: Sendable, Equatable {
  case text
  /// Unstructured JSON response (no schema enforcement at the provider).
  case json(name: String? = nil, description: String? = nil)
  /// Structured JSON response constrained by a JSON Schema.
  case jsonSchema(schema: JSONSchema, name: String? = nil, description: String? = nil)
}
