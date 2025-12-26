import Foundation
import AIKit

@attached(extension, conformances: SchemaProviding)
@attached(member, names: named(schema), named(Partial))
public macro AIModel() = #externalMacro(
  module: "AIKitMacros",
  type: "AIModelMacro"
)

@attached(peer)
public macro Field(
  _ description: String,
  minLength: Int? = nil,
  maxLength: Int? = nil,
  pattern: String? = nil,
  range: ClosedRange<Double>? = nil,
  enum values: [String]? = nil,
  minItems: Int? = nil,
  maxItems: Int? = nil,
  format: String? = nil
) = #externalMacro(
  module: "AIKitMacros",
  type: "FieldMacro"
)

