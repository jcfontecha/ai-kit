import Foundation
import AIKitProviders

public protocol SchemaProviding: Codable, Sendable {
  associatedtype Partial: Codable & Sendable
  static var schema: ObjectSchema<Self> { get }
}

public struct ObjectSchema<T: Codable & Sendable>: Sendable {
  public var jsonSchema: JSONSchema
  public var name: String?
  public var description: String?

  public init(jsonSchema: JSONSchema, name: String? = nil, description: String? = nil) {
    self.jsonSchema = jsonSchema
    self.name = name
    self.description = description
  }

  public static func manual(
    jsonSchema: JSONSchema,
    name: String,
    description: String? = nil
  ) -> ObjectSchema<T> {
    .init(jsonSchema: jsonSchema, name: name, description: description)
  }
}

