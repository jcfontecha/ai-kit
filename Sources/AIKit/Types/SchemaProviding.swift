import Foundation

// MARK: - Core Protocol for Schema Providing Types

/// Protocol for types that can provide their own schema.
/// This creates a compile-time contract ensuring types define their schemas.
public protocol SchemaProviding: Codable, Sendable {
    /// The schema definition for this type.
    static var schema: ObjectSchema<Self> { get }
}

// MARK: - Result Builder for Schema Definition

/// A result builder that enables declarative schema definition.
/// This provides a SwiftUI-like syntax for building schemas.
@resultBuilder
public struct ObjectSchemaBuilder {
    public static func buildBlock(_ components: SchemaProperty...) -> [SchemaProperty] {
        Array(components)
    }
    
    public static func buildOptional(_ component: SchemaProperty?) -> SchemaProperty? {
        component
    }
    
    public static func buildEither(first component: SchemaProperty) -> SchemaProperty {
        component
    }
    
    public static func buildEither(second component: SchemaProperty) -> SchemaProperty {
        component
    }
    
    public static func buildArray(_ components: [SchemaProperty]) -> [SchemaProperty] {
        components
    }
}

// MARK: - Schema Property Definition

/// Represents a single property in a schema.
public struct SchemaProperty {
    let key: String
    let schema: JSONSchema
    let required: Bool
    
    init(key: String, schema: JSONSchema, required: Bool = true) {
        self.key = key
        self.schema = schema
        self.required = required
    }
}

// MARK: - Schema Property Builders

/// Namespace for schema property builders.
public enum Schema {
    
    /// Define a string property.
    public static func string(
        _ key: String,
        description: String? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        format: String? = nil,
        enum values: [String]? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .string(
                minLength: minLength,
                maxLength: maxLength,
                pattern: pattern,
                format: format,
                enum: values
            ).withDescription(description),
            required: required
        )
    }
    
    /// Define an integer property.
    public static func integer(
        _ key: String,
        description: String? = nil,
        minimum: Int? = nil,
        maximum: Int? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .integer(
                minimum: minimum.map(Double.init),
                maximum: maximum.map(Double.init)
            ).withDescription(description),
            required: required
        )
    }
    
    /// Define a number property.
    public static func number(
        _ key: String,
        description: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .number(
                minimum: minimum,
                maximum: maximum
            ).withDescription(description),
            required: required
        )
    }
    
    /// Define a boolean property.
    public static func boolean(
        _ key: String,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .boolean().withDescription(description),
            required: required
        )
    }
    
    /// Define an array property.
    public static func array<T: SchemaProviding>(
        _ key: String,
        of type: T.Type,
        description: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .array(
                items: type.schema.jsonSchema,
                minItems: minItems,
                maxItems: maxItems,
                uniqueItems: uniqueItems
            ).withDescription(description),
            required: required
        )
    }
    
    /// Define an array property with custom element schema.
    public static func array(
        _ key: String,
        elementSchema: JSONSchema,
        description: String? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .array(
                items: elementSchema,
                minItems: minItems,
                maxItems: maxItems,
                uniqueItems: uniqueItems
            ).withDescription(description),
            required: required
        )
    }
    
    /// Define an object property using a SchemaProviding type.
    public static func object<T: SchemaProviding>(
        _ key: String,
        of type: T.Type,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: type.schema.jsonSchema.withDescription(description),
            required: required
        )
    }
    
    /// Define an object property with custom schema.
    public static func object(
        _ key: String,
        schema: JSONSchema,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: schema.withDescription(description),
            required: required
        )
    }
    
    /// Define a date property.
    public static func date(
        _ key: String,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .string(format: "date-time").withDescription(description),
            required: required
        )
    }
    
    /// Define a UUID property.
    public static func uuid(
        _ key: String,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .string(format: "uuid").withDescription(description),
            required: required
        )
    }
    
    /// Define a URL property.
    public static func url(
        _ key: String,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .string(format: "uri").withDescription(description),
            required: required
        )
    }
    
    /// Define an email property.
    public static func email(
        _ key: String,
        description: String? = nil,
        required: Bool = true
    ) -> SchemaProperty {
        SchemaProperty(
            key: key,
            schema: .string(format: "email").withDescription(description),
            required: required
        )
    }
}

// MARK: - Enhanced ObjectSchema

public extension ObjectSchema {
    
    /// Create a schema using the result builder syntax.
    static func define(
        name: String? = nil,
        description: String? = nil,
        allowAdditionalProperties: Bool = false,
        @ObjectSchemaBuilder properties: () -> [SchemaProperty]
    ) -> ObjectSchema<T> {
        let props = properties()
        
        var schemaProperties: [String: JSONSchema] = [:]
        var required: [String] = []
        
        for prop in props {
            schemaProperties[prop.key] = prop.schema
            if prop.required {
                required.append(prop.key)
            }
        }
        
        let jsonSchema = JSONSchema.object(
            properties: schemaProperties,
            required: required,
            additionalProperties: .boolean(allowAdditionalProperties)
        )
        
        return ObjectSchema(
            jsonSchema: jsonSchema,
            name: name ?? String(describing: T.self),
            description: description
        )
    }
}

// MARK: - Convenience Extensions for Common Types

extension String: SchemaProviding {
    public static var schema: ObjectSchema<String> {
        ObjectSchema(jsonSchema: .string(), name: "String")
    }
}

extension Int: SchemaProviding {
    public static var schema: ObjectSchema<Int> {
        ObjectSchema(jsonSchema: .integer(), name: "Int")
    }
}

extension Double: SchemaProviding {
    public static var schema: ObjectSchema<Double> {
        ObjectSchema(jsonSchema: .number(), name: "Double")
    }
}

extension Bool: SchemaProviding {
    public static var schema: ObjectSchema<Bool> {
        ObjectSchema(jsonSchema: .boolean(), name: "Bool")
    }
}

extension Date: SchemaProviding {
    public static var schema: ObjectSchema<Date> {
        ObjectSchema(jsonSchema: .string(format: "date-time"), name: "Date")
    }
}

extension URL: SchemaProviding {
    public static var schema: ObjectSchema<URL> {
        ObjectSchema(jsonSchema: .string(format: "uri"), name: "URL")
    }
}

extension UUID: SchemaProviding {
    public static var schema: ObjectSchema<UUID> {
        ObjectSchema(jsonSchema: .string(format: "uuid"), name: "UUID")
    }
}

// Make Array conform when Element conforms
extension Array: SchemaProviding where Element: SchemaProviding {
    public static var schema: ObjectSchema<Array<Element>> {
        ObjectSchema(
            jsonSchema: .array(items: Element.schema.jsonSchema),
            name: "Array<\(Element.self)>"
        )
    }
}

// Make Optional conform when Wrapped conforms
extension Optional: SchemaProviding where Wrapped: SchemaProviding {
    public static var schema: ObjectSchema<Optional<Wrapped>> {
        // Create a schema that allows either the wrapped type or null
        let wrappedSchema = Wrapped.schema.jsonSchema
        
        let optionalSchema = JSONSchema.definition(SchemaDefinition(
            type: .object,
            oneOf: [wrappedSchema, .definition(SchemaDefinition(type: .null))]
        ))
        
        return ObjectSchema(
            jsonSchema: optionalSchema,
            name: "\(Wrapped.self)?"
        )
    }
}


// MARK: - JSON Schema Extension Helper

private extension JSONSchema {
    func withDescription(_ description: String?) -> JSONSchema {
        guard let description = description else { return self }
        
        switch self {
        case .definition(var def):
            def = SchemaDefinition(
                type: def.type,
                properties: def.properties,
                items: def.items,
                required: def.required,
                enum: def.enum,
                const: def.const,
                title: def.title,
                description: description,
                examples: def.examples,
                format: def.format,
                pattern: def.pattern,
                minimum: def.minimum,
                maximum: def.maximum,
                exclusiveMinimum: def.exclusiveMinimum,
                exclusiveMaximum: def.exclusiveMaximum,
                minLength: def.minLength,
                maxLength: def.maxLength,
                minItems: def.minItems,
                maxItems: def.maxItems,
                uniqueItems: def.uniqueItems,
                minProperties: def.minProperties,
                maxProperties: def.maxProperties,
                additionalProperties: def.additionalProperties,
                oneOf: def.oneOf,
                anyOf: def.anyOf,
                allOf: def.allOf,
                not: def.not
            )
            return .definition(def)
        }
    }
}