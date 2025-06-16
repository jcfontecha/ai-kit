import Foundation

// MARK: - JSON Schema

/// JSON Schema definition for structured data validation
public indirect enum JSONSchema: Codable, Sendable {
    case definition(SchemaDefinition)
    
    public var definition: SchemaDefinition {
        switch self {
        case .definition(let def):
            return def
        }
    }
}

public struct SchemaDefinition: Codable, Sendable {
    public let type: JSONSchemaType
    public let properties: [String: JSONSchema]?
    public let items: JSONSchema?
    public let required: [String]?
    public let `enum`: [JSONSchemaValue]?
    public let const: JSONSchemaValue?
    public let title: String?
    public let description: String?
    public let examples: [JSONSchemaValue]?
    public let format: String?
    public let pattern: String?
    public let minimum: Double?
    public let maximum: Double?
    public let exclusiveMinimum: Double?
    public let exclusiveMaximum: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let minItems: Int?
    public let maxItems: Int?
    public let uniqueItems: Bool?
    public let minProperties: Int?
    public let maxProperties: Int?
    public let additionalProperties: AdditionalProperties?
    public let oneOf: [JSONSchema]?
    public let anyOf: [JSONSchema]?
    public let allOf: [JSONSchema]?
    public let not: JSONSchema?
    
    public init(
        type: JSONSchemaType,
        properties: [String: JSONSchema]? = nil,
        items: JSONSchema? = nil,
        required: [String]? = nil,
        enum: [JSONSchemaValue]? = nil,
        const: JSONSchemaValue? = nil,
        title: String? = nil,
        description: String? = nil,
        examples: [JSONSchemaValue]? = nil,
        format: String? = nil,
        pattern: String? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil,
        exclusiveMaximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil,
        minProperties: Int? = nil,
        maxProperties: Int? = nil,
        additionalProperties: AdditionalProperties? = nil,
        oneOf: [JSONSchema]? = nil,
        anyOf: [JSONSchema]? = nil,
        allOf: [JSONSchema]? = nil,
        not: JSONSchema? = nil
    ) {
        self.type = type
        self.properties = properties
        self.items = items
        self.required = required
        self.`enum` = `enum`
        self.const = const
        self.title = title
        self.description = description
        self.examples = examples
        self.format = format
        self.pattern = pattern
        self.minimum = minimum
        self.maximum = maximum
        self.exclusiveMinimum = exclusiveMinimum
        self.exclusiveMaximum = exclusiveMaximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.minItems = minItems
        self.maxItems = maxItems
        self.uniqueItems = uniqueItems
        self.minProperties = minProperties
        self.maxProperties = maxProperties
        self.additionalProperties = additionalProperties
        self.oneOf = oneOf
        self.anyOf = anyOf
        self.allOf = allOf
        self.not = not
    }
}

// MARK: - JSON Schema Types

/// JSON Schema primitive types
public enum JSONSchemaType: String, Codable, Sendable {
    case string
    case number
    case integer
    case boolean
    case array
    case object
    case null
}

/// JSON Schema values for enums and constants
public enum JSONSchemaValue: Codable, Sendable {
    case string(String)
    case integer(Int)
    case number(Double)
    case boolean(Bool)
    case null
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .integer(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(
                JSONSchemaValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid JSON schema value")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// Additional properties configuration
public indirect enum AdditionalProperties: Codable, Sendable {
    case boolean(Bool)
    case schema(JSONSchema)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let schema = try? container.decode(JSONSchema.self) {
            self = .schema(schema)
        } else {
            throw DecodingError.typeMismatch(
                AdditionalProperties.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid additional properties")
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .schema(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Schema Validation

/// Protocol for schema validation
public protocol SchemaValidator: Sendable {
    /// Validate data against a schema
    func validate(_ data: Data, against schema: JSONSchema) throws -> ValidationResult
    
    /// Validate partial JSON during streaming
    func validatePartial(_ partialJSON: String, against schema: JSONSchema) throws -> PartialValidationResult
}

/// Result of schema validation
public struct ValidationResult: Sendable {
    public let isValid: Bool
    public let errors: [ValidationError]
    public let warnings: [ValidationWarning]
    
    public init(isValid: Bool, errors: [ValidationError] = [], warnings: [ValidationWarning] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
}

/// Result of partial schema validation during streaming
public struct PartialValidationResult: Sendable {
    public let isValidSoFar: Bool
    public let canContinue: Bool
    public let errors: [ValidationError]
    public let suggestions: [CompletionSuggestion]
    
    public init(
        isValidSoFar: Bool,
        canContinue: Bool,
        errors: [ValidationError] = [],
        suggestions: [CompletionSuggestion] = []
    ) {
        self.isValidSoFar = isValidSoFar
        self.canContinue = canContinue
        self.errors = errors
        self.suggestions = suggestions
    }
}

/// Schema validation error
public struct ValidationError: Error, Sendable {
    public let path: String
    public let message: String
    public let code: ValidationErrorCode
    
    public init(path: String, message: String, code: ValidationErrorCode) {
        self.path = path
        self.message = message
        self.code = code
    }
}

/// Schema validation warning
public struct ValidationWarning: Sendable {
    public let path: String
    public let message: String
    public let code: ValidationWarningCode
    
    public init(path: String, message: String, code: ValidationWarningCode) {
        self.path = path
        self.message = message
        self.code = code
    }
}

/// Completion suggestion for partial validation
public struct CompletionSuggestion: Sendable {
    public let type: CompletionType
    public let suggestion: String
    public let description: String?
    
    public init(type: CompletionType, suggestion: String, description: String? = nil) {
        self.type = type
        self.suggestion = suggestion
        self.description = description
    }
}

/// Types of validation errors
public enum ValidationErrorCode: String, Codable, Sendable {
    case typeMismatch
    case missingProperty
    case invalidValue
    case constraintViolation
    case formatError
    case patternMismatch
    case enumViolation
}

/// Types of validation warnings
public enum ValidationWarningCode: String, Codable, Sendable {
    case deprecatedProperty
    case unknownProperty
    case performanceWarning
}

/// Types of completion suggestions
public enum CompletionType: String, Codable, Sendable {
    case closeBrace
    case closeBracket
    case closeQuote
    case addComma
    case addProperty
    case completeValue
}

// MARK: - Schema Builder

/// Builder for creating JSON schemas
@resultBuilder
public struct SchemaBuilder {
    public static func buildBlock(_ components: JSONSchema...) -> [JSONSchema] {
        components
    }
    
    public static func buildOptional(_ component: JSONSchema?) -> JSONSchema? {
        component
    }
    
    public static func buildEither(first component: JSONSchema) -> JSONSchema {
        component
    }
    
    public static func buildEither(second component: JSONSchema) -> JSONSchema {
        component
    }
    
    public static func buildArray(_ components: [JSONSchema]) -> [JSONSchema] {
        components
    }
}

// MARK: - Schema Convenience Extensions

public extension JSONSchema {
    /// Create string schema
    static func string(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil,
        format: String? = nil,
        `enum`: [String]? = nil
    ) -> JSONSchema {
        .definition(SchemaDefinition(
            type: .string,
            enum: `enum`?.map { .string($0) },
            format: format,
            pattern: pattern,
            minLength: minLength,
            maxLength: maxLength
        ))
    }
    
    /// Create number schema
    static func number(
        minimum: Double? = nil,
        maximum: Double? = nil,
        exclusiveMinimum: Double? = nil,
        exclusiveMaximum: Double? = nil
    ) -> JSONSchema {
        .definition(SchemaDefinition(
            type: .number,
            minimum: minimum,
            maximum: maximum,
            exclusiveMinimum: exclusiveMinimum,
            exclusiveMaximum: exclusiveMaximum
        ))
    }
    
    /// Create integer schema
    static func integer(
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> JSONSchema {
        .definition(SchemaDefinition(
            type: .integer,
            minimum: minimum,
            maximum: maximum
        ))
    }
    
    /// Create boolean schema
    static func boolean() -> JSONSchema {
        .definition(SchemaDefinition(type: .boolean))
    }
    
    /// Create array schema
    static func array(
        items: JSONSchema,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        uniqueItems: Bool? = nil
    ) -> JSONSchema {
        .definition(SchemaDefinition(
            type: .array,
            items: items,
            minItems: minItems,
            maxItems: maxItems,
            uniqueItems: uniqueItems
        ))
    }
    
    /// Create object schema
    static func object(
        properties: [String: JSONSchema],
        required: [String]? = nil,
        additionalProperties: AdditionalProperties? = nil
    ) -> JSONSchema {
        .definition(SchemaDefinition(
            type: .object,
            properties: properties,
            required: required,
            additionalProperties: additionalProperties
        ))
    }
}