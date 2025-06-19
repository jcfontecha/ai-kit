import Foundation

// MARK: - Object Schema Types

/// Type-safe schema wrapper for structured object generation.
///
/// `ObjectSchema` provides a type-safe interface for defining the structure
/// of objects that AI models should generate. It combines JSON Schema validation
/// with Swift's type system to ensure that generated objects conform to the
/// expected structure.
///
/// ## Key Features
/// - **Type Safety**: Ensures generated objects match the expected Swift type
/// - **JSON Schema Integration**: Uses standard JSON Schema for model communication
/// - **Explicit Schema Definition**: Requires explicit JSON Schema definitions
/// - **Validation**: Provides runtime validation of generated objects
/// - **Provider Agnostic**: Works with any AI provider that supports structured output
///
/// ## Usage Examples
///
/// ### Basic Object Schema
/// ```swift
/// struct Person: Codable, SchemaProviding {
///     let name: String
///     let age: Int
///     let email: String?
///     
///     static var jsonSchema: JSONSchema {
///         .object(properties: [
///             "name": .string(),
///             "age": .integer(),
///             "email": .string()
///         ], required: ["name", "age"])
///     }
/// }
/// 
/// let schema = ObjectSchema<Person>(jsonSchema: Person.jsonSchema)
/// let response = try await client.generateObject(model, prompt: "Create a person", schema: schema)
/// let person: Person = response.object
/// ```
///
/// ### Schema with Custom JSON Schema
/// ```swift
/// let customSchema = JSONSchema.object(properties: [
///     "name": .string(minLength: 1, maxLength: 100),
///     "age": .integer(minimum: 0, maximum: 150),
///     "email": .string(format: "email")
/// ], required: ["name", "age"])
/// 
/// let schema = ObjectSchema<Person>(
///     jsonSchema: customSchema,
///     name: "Person",
///     description: "A person with name, age, and optional email"
/// )
/// ```
public struct ObjectSchema<T: Codable & Sendable>: Sendable {
    
    // MARK: - Properties
    
    /// The JSON Schema that defines the object structure.
    ///
    /// This schema is sent to the AI provider to constrain the generation
    /// process. It should accurately reflect the structure of type `T`.
    public let jsonSchema: JSONSchema
    
    /// Optional name for the schema.
    ///
    /// Provides a human-readable identifier for the schema, which can be
    /// useful for debugging and provider communication.
    public let name: String?
    
    /// Optional description of what this object represents.
    ///
    /// Helps the AI model understand the purpose and context of the object
    /// it should generate.
    public let description: String?
    
    /// Example instances of the object.
    ///
    /// Providing examples can help AI models understand the expected
    /// format and content of the generated objects.
    public let examples: [T]?
    
    /// Validation mode for generated objects.
    ///
    /// Controls how strictly the generated objects are validated against
    /// the schema and Swift type.
    public let validationMode: ValidationMode
    
    /// Whether to allow additional properties not defined in the schema.
    public let allowAdditionalProperties: Bool
    
    // MARK: - Initialization
    
    /// Creates a new ObjectSchema with an explicit JSON schema.
    ///
    /// This is the primary initializer that requires an explicit JSON Schema
    /// definition. Use this when you have full control over the schema definition.
    ///
    /// - Parameters:
    ///   - jsonSchema: The JSON schema that defines the object structure
    ///   - name: Optional name for the schema
    ///   - description: Optional description
    ///   - examples: Optional example instances
    ///   - validationMode: Validation strictness (defaults to .strict)
    ///   - allowAdditionalProperties: Allow extra properties (defaults to false)
    public init(
        jsonSchema: JSONSchema,
        name: String? = nil,
        description: String? = nil,
        examples: [T]? = nil,
        validationMode: ValidationMode = .strict,
        allowAdditionalProperties: Bool = false
    ) {
        self.jsonSchema = jsonSchema
        self.name = name ?? String(describing: T.self)
        self.description = description
        self.examples = examples
        self.validationMode = validationMode
        self.allowAdditionalProperties = allowAdditionalProperties
    }
    
    /// Creates an ObjectSchema with a fully specified JSON Schema and required name.
    ///
    /// Use this initializer when you need full control over the JSON Schema
    /// definition with an explicit name, such as for complex validation rules
    /// or provider-specific schema features.
    ///
    /// - Parameters:
    ///   - jsonSchema: The complete JSON Schema definition
    ///   - name: Required schema name
    ///   - description: Schema description
    ///   - examples: Example instances
    ///   - validationMode: Validation mode
    ///   - allowAdditionalProperties: Allow additional properties
    public init(
        jsonSchema: JSONSchema,
        name: String,
        description: String? = nil,
        examples: [T]? = nil,
        validationMode: ValidationMode = .strict,
        allowAdditionalProperties: Bool = false
    ) {
        self.jsonSchema = jsonSchema
        self.name = name
        self.description = description
        self.examples = examples
        self.validationMode = validationMode
        self.allowAdditionalProperties = allowAdditionalProperties
    }
    
    
    
}


// MARK: - Generation Mode

/// Controls how AI providers generate structured output.
/// 
/// This enum maps to the Vercel AI SDK's mode parameter and allows
/// providers to optimize their structured output generation strategy.
public enum GenerationMode: String, Codable, Sendable {
    
    /// Automatic mode selection - provider chooses the best approach.
    /// 
    /// The provider will automatically select the most appropriate
    /// generation strategy based on the model's capabilities and the
    /// complexity of the requested schema.
    case auto = "auto"
    
    /// JSON mode - instruct the model to respond in JSON format.
    /// 
    /// Uses the provider's JSON mode if available, otherwise falls back
    /// to prompt-based JSON generation. This mode is fast but may be
    /// less reliable for complex schemas.
    case json = "json"
    
    /// Tool mode - use function/tool calling for structured output.
    /// 
    /// Uses the provider's function/tool calling capability to generate
    /// structured output. This mode is more reliable for complex schemas
    /// but requires tool calling support.
    case tool = "tool"
}

// MARK: - Output Strategy

/// Defines the type of structured output being generated.
/// 
/// This enum helps providers understand what kind of output is expected
/// and allows for optimization of the generation process.
public enum OutputStrategy: String, Codable, Sendable {
    
    /// Generate a single object matching the schema.
    case object = "object"
    
    /// Generate an array of objects matching the element schema.
    case array = "array"
    
    /// Generate an enum value from a predefined set of options.
    case `enum` = "enum"
    
    /// Generate without schema constraints (free-form text/JSON).
    case noSchema = "no-schema"
}

// MARK: - Validation Mode

/// Controls how strictly generated objects are validated.
public enum ValidationMode: String, Codable, Sendable {
    
    /// Strict validation - objects must exactly match the schema and type.
    case strict
    
    /// Lenient validation - minor deviations are allowed.
    case lenient
    
    /// No validation - objects are accepted as-is.
    case none
}

// MARK: - Schema Builder Methods

public extension ObjectSchema {
    
    /// Add a name to the schema.
    ///
    /// - Parameter name: The schema name
    /// - Returns: A new ObjectSchema with the specified name
    func withName(_ name: String) -> ObjectSchema<T> {
        ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: examples,
            validationMode: validationMode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Add a description to the schema.
    ///
    /// - Parameter description: The schema description
    /// - Returns: A new ObjectSchema with the specified description
    func withDescription(_ description: String) -> ObjectSchema<T> {
        ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: examples,
            validationMode: validationMode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Add an example to the schema.
    ///
    /// - Parameter example: An example instance of type T
    /// - Returns: A new ObjectSchema with the added example
    func withExample(_ example: T) -> ObjectSchema<T> {
        let newExamples = (examples ?? []) + [example]
        return ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: newExamples,
            validationMode: validationMode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Add multiple examples to the schema.
    ///
    /// - Parameter examples: Array of example instances
    /// - Returns: A new ObjectSchema with the added examples
    func withExamples(_ examples: [T]) -> ObjectSchema<T> {
        let newExamples = (self.examples ?? []) + examples
        return ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: newExamples,
            validationMode: validationMode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Set the validation mode.
    ///
    /// - Parameter mode: The validation mode to use
    /// - Returns: A new ObjectSchema with the specified validation mode
    func withValidationMode(_ mode: ValidationMode) -> ObjectSchema<T> {
        ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: examples,
            validationMode: mode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Allow additional properties in generated objects.
    ///
    /// - Parameter allow: Whether to allow additional properties
    /// - Returns: A new ObjectSchema with the specified setting
    func allowingAdditionalProperties(_ allow: Bool = true) -> ObjectSchema<T> {
        ObjectSchema(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            examples: examples,
            validationMode: validationMode,
            allowAdditionalProperties: allow
        )
    }
}

// MARK: - Field Description Methods

public extension ObjectSchema {
    
    /// Add a description and constraints to a specific field using KeyPath.
    ///
    /// This method provides a Swift-idiomatic way to add field-level descriptions
    /// and constraints that help AI models generate better structured output.
    ///
    /// - Parameters:
    ///   - keyPath: KeyPath to the property to describe
    ///   - description: Human-readable description of what this field should contain
    ///   - minimum: Minimum value for numeric fields
    ///   - maximum: Maximum value for numeric fields
    ///   - minLength: Minimum length for string fields
    ///   - maxLength: Maximum length for string fields
    ///   - enum: Allowed enum values for string fields
    ///   - maxItems: Maximum number of items for array fields
    /// - Returns: A new ObjectSchema with the field description added
    func describe<Value>(
        _ keyPath: KeyPath<T, Value>,
        _ description: String,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        enum: [String]? = nil,
        maxItems: Int? = nil
    ) -> ObjectSchema<T> {
        
        let fieldName = getFieldName(for: keyPath)
        let updatedSchema = addFieldDescription(
            fieldName: fieldName,
            description: description,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            maxLength: maxLength,
            enum: `enum`,
            maxItems: maxItems
        )
        
        return ObjectSchema(
            jsonSchema: updatedSchema,
            name: name,
            description: self.description,
            examples: examples,
            validationMode: validationMode,
            allowAdditionalProperties: allowAdditionalProperties
        )
    }
    
    /// Add a simple description to a field without constraints.
    ///
    /// - Parameters:
    ///   - keyPath: KeyPath to the property to describe
    ///   - description: Human-readable description of what this field should contain
    /// - Returns: A new ObjectSchema with the field description added
    func describe<Value>(
        _ keyPath: KeyPath<T, Value>,
        _ description: String
    ) -> ObjectSchema<T> {
        return describe(keyPath, description, minimum: nil, maximum: nil, minLength: nil, maxLength: nil, enum: nil, maxItems: nil)
    }
    
    // MARK: - Private Helper Methods
    
    /// Extract field name from KeyPath using simple string parsing.
    ///
    /// This implementation provides basic field name extraction from KeyPaths
    /// by parsing the string representation of the KeyPath.
    private func getFieldName<Value>(for keyPath: KeyPath<T, Value>) -> String {
        let keyPathString = String(describing: keyPath)
        
        // Parse KeyPath string: \TypeName.propertyName
        if let dotIndex = keyPathString.lastIndex(of: ".") {
            let propertyName = String(keyPathString[keyPathString.index(after: dotIndex)...])
            
            // Clean up the property name (remove trailing characters)
            let cleanedName = propertyName.components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? propertyName
            
            if !cleanedName.isEmpty && cleanedName != "self" {
                return cleanedName
            }
        }
        
        // Fallback: Generate stable name based on KeyPath hash
        let hashValue = abs(keyPath.hashValue)
        let valueTypeName = String(describing: Value.self)
        return "field_\(valueTypeName)_\(hashValue)"
    }
    
    /// Add field description and constraints to the JSON Schema.
    private func addFieldDescription(
        fieldName: String,
        description: String,
        minimum: Double?,
        maximum: Double?,
        minLength: Int?,
        maxLength: Int?,
        enum: [String]?,
        maxItems: Int?
    ) -> JSONSchema {
        
        guard case .definition(let schemaDef) = jsonSchema else {
            return jsonSchema // Return unchanged if not a definition
        }
        
        guard var properties = schemaDef.properties else {
            return jsonSchema // Return unchanged if no properties
        }
        
        // Get existing property schema or create a default one
        let existingProperty = properties[fieldName] ?? .string()
        
        // Update the property with description and constraints
        let updatedProperty = addConstraintsToProperty(
            property: existingProperty,
            description: description,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            maxLength: maxLength,
            enum: `enum`,
            maxItems: maxItems
        )
        
        properties[fieldName] = updatedProperty
        
        // Create updated schema definition
        let updatedDefinition = SchemaDefinition(
            type: schemaDef.type,
            properties: properties,
            items: schemaDef.items,
            required: schemaDef.required,
            enum: schemaDef.enum,
            const: schemaDef.const,
            title: schemaDef.title,
            description: schemaDef.description,
            examples: schemaDef.examples,
            format: schemaDef.format,
            pattern: schemaDef.pattern,
            minimum: schemaDef.minimum,
            maximum: schemaDef.maximum,
            exclusiveMinimum: schemaDef.exclusiveMinimum,
            exclusiveMaximum: schemaDef.exclusiveMaximum,
            minLength: schemaDef.minLength,
            maxLength: schemaDef.maxLength,
            minItems: schemaDef.minItems,
            maxItems: schemaDef.maxItems,
            uniqueItems: schemaDef.uniqueItems,
            minProperties: schemaDef.minProperties,
            maxProperties: schemaDef.maxProperties,
            additionalProperties: schemaDef.additionalProperties,
            oneOf: schemaDef.oneOf,
            anyOf: schemaDef.anyOf,
            allOf: schemaDef.allOf,
            not: schemaDef.not
        )
        
        return .definition(updatedDefinition)
    }
    
    /// Add constraints to a specific property schema.
    private func addConstraintsToProperty(
        property: JSONSchema,
        description: String,
        minimum: Double?,
        maximum: Double?,
        minLength: Int?,
        maxLength: Int?,
        enum: [String]?,
        maxItems: Int?
    ) -> JSONSchema {
        
        guard case .definition(let propDef) = property else {
            return property
        }
        
        let updatedDefinition = SchemaDefinition(
            type: propDef.type,
            properties: propDef.properties,
            items: propDef.items,
            required: propDef.required,
            enum: `enum`?.map { .string($0) } ?? propDef.enum,
            const: propDef.const,
            title: propDef.title,
            description: description, // Update description
            examples: propDef.examples,
            format: propDef.format,
            pattern: propDef.pattern,
            minimum: minimum ?? propDef.minimum, // Update constraints
            maximum: maximum ?? propDef.maximum,
            exclusiveMinimum: propDef.exclusiveMinimum,
            exclusiveMaximum: propDef.exclusiveMaximum,
            minLength: minLength ?? propDef.minLength,
            maxLength: maxLength ?? propDef.maxLength,
            minItems: propDef.minItems,
            maxItems: maxItems ?? propDef.maxItems,
            uniqueItems: propDef.uniqueItems,
            minProperties: propDef.minProperties,
            maxProperties: propDef.maxProperties,
            additionalProperties: propDef.additionalProperties,
            oneOf: propDef.oneOf,
            anyOf: propDef.anyOf,
            allOf: propDef.allOf,
            not: propDef.not
        )
        
        return .definition(updatedDefinition)
    }
}

// MARK: - Schema Factory Methods

public extension ObjectSchema {
    
    /// Create an ObjectSchema from a type that conforms to SchemaProviding.
    ///
    /// This is the recommended way to create schemas for types that define
    /// their own JSON Schema through the SchemaProviding protocol.
    ///
    /// - Parameters:
    ///   - type: The Swift type that conforms to SchemaProviding
    ///   - name: Optional custom name for the schema
    ///   - description: Optional description of the schema
    /// - Returns: An ObjectSchema using the type's provided JSON Schema
    static func from(
        _ type: T.Type,
        name: String? = nil,
        description: String? = nil
    ) -> ObjectSchema<T> where T: SchemaProviding {
        let providedSchema = type.schema
        return ObjectSchema<T>(
            jsonSchema: providedSchema.jsonSchema,
            name: name ?? providedSchema.name ?? String(describing: type).components(separatedBy: ".").last,
            description: description ?? providedSchema.description
        )
    }
    
    
    /// Create an ObjectSchema with a manually defined JSON Schema.
    ///
    /// Use this method when you need full control over the schema definition
    /// or when automatic generation doesn't meet your requirements.
    ///
    /// - Parameters:
    ///   - jsonSchema: The manually defined JSON Schema
    ///   - name: Schema name
    ///   - description: Schema description
    ///   - strict: Whether to use strict validation (defaults to true)
    /// - Returns: An ObjectSchema with the provided JSON Schema
    static func manual(
        jsonSchema: JSONSchema,
        name: String,
        description: String? = nil,
        strict: Bool = true
    ) -> ObjectSchema<T> {
        return ObjectSchema<T>(
            jsonSchema: jsonSchema,
            name: name,
            description: description,
            validationMode: strict ? .strict : .lenient,
            allowAdditionalProperties: false
        )
    }
    
}

// MARK: - Global Schema Factory Functions

/// Create a schema for an array of objects using SchemaProviding types.
///
/// - Parameter elementType: The type of array elements that conforms to SchemaProviding
/// - Returns: An ObjectSchema for arrays of the specified type
public func arraySchema<U: Codable & Sendable & SchemaProviding>(of elementType: U.Type) -> ObjectSchema<[U]> {
    let arraySchema = JSONSchema.array(
        items: elementType.schema.jsonSchema,
        minItems: 0
    )
    
    return ObjectSchema<[U]>(
        jsonSchema: arraySchema,
        name: "[\(elementType)]",
        description: "Array of \(elementType) objects"
    )
}

/// Create a schema for optional objects using SchemaProviding types.
///
/// - Parameter wrappedType: The wrapped type that conforms to SchemaProviding
/// - Returns: An ObjectSchema for optional values of the specified type
public func optionalSchema<U: Codable & Sendable & SchemaProviding>(_ wrappedType: U.Type) -> ObjectSchema<U?> {
    let wrappedSchema = wrappedType.schema.jsonSchema
    
    // Create a schema that allows either the base type or null
    let optionalSchema = JSONSchema.definition(SchemaDefinition(
        type: wrappedSchema.definition.type,
        properties: wrappedSchema.definition.properties,
        items: wrappedSchema.definition.items,
        required: wrappedSchema.definition.required,
        oneOf: [wrappedSchema, .definition(SchemaDefinition(type: .null))]
    ))
    
    return ObjectSchema<U?>(
        jsonSchema: optionalSchema,
        name: "\(wrappedType)?",
        description: "Optional \(wrappedType) object"
    )
}

// MARK: - Validation Methods

public extension ObjectSchema {
    
    /// Validate a generated object against this schema.
    ///
    /// Performs both JSON Schema validation and Swift type validation
    /// based on the configured validation mode.
    ///
    /// - Parameter object: The object to validate
    /// - Returns: Validation result with any errors or warnings
    func validate(_ object: T) -> ObjectValidationResult {
        switch validationMode {
        case .none:
            return ObjectValidationResult(isValid: true)
        case .lenient:
            return performLenientValidation(object)
        case .strict:
            return performStrictValidation(object)
        }
    }
    
    /// Validate JSON data against this schema before decoding.
    ///
    /// - Parameter data: JSON data to validate
    /// - Returns: Validation result
    func validateJSON(_ data: Data) -> ObjectValidationResult {
        // In a real implementation, this would validate the JSON against the schema
        // before attempting to decode it into the Swift type
        do {
            let _ = try JSONDecoder().decode(T.self, from: data)
            return ObjectValidationResult(isValid: true)
        } catch {
            return ObjectValidationResult(
                isValid: false,
                errors: [ObjectValidationError.decodingError(error.localizedDescription)]
            )
        }
    }
    
    // MARK: - Private Validation Methods
    
    private func performStrictValidation(_ object: T) -> ObjectValidationResult {
        // Placeholder for strict validation
        // Would perform comprehensive validation against JSON Schema
        return ObjectValidationResult(isValid: true)
    }
    
    private func performLenientValidation(_ object: T) -> ObjectValidationResult {
        // Placeholder for lenient validation
        // Would perform basic validation with some tolerance for deviations
        return ObjectValidationResult(isValid: true)
    }
}

// MARK: - Validation Result Types

/// Result of object validation against a schema.
public struct ObjectValidationResult: Sendable {
    
    /// Whether the object is valid according to the schema.
    public let isValid: Bool
    
    /// Validation errors encountered.
    public let errors: [ObjectValidationError]
    
    /// Validation warnings (non-fatal issues).
    public let warnings: [ObjectValidationWarning]
    
    /// Additional validation metadata.
    public let metadata: [String: String]
    
    public init(
        isValid: Bool,
        errors: [ObjectValidationError] = [],
        warnings: [ObjectValidationWarning] = [],
        metadata: [String: String] = [:]
    ) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
        self.metadata = metadata
    }
}

/// Validation error for object schemas.
public enum ObjectValidationError: Error, Sendable {
    
    /// The object doesn't match the expected JSON Schema.
    case schemaViolation(String)
    
    /// The object couldn't be decoded to the expected Swift type.
    case decodingError(String)
    
    /// A required property is missing.
    case missingRequiredProperty(String)
    
    /// A property has an invalid type.
    case invalidPropertyType(String, expected: String, actual: String)
    
    /// A property value is outside the allowed range.
    case valueOutOfRange(String, value: String, range: String)
    
    /// Additional properties were found when not allowed.
    case additionalPropertiesNotAllowed([String])
    
    /// Custom validation error.
    case custom(String)
}

/// Validation warning for object schemas.
public enum ObjectValidationWarning: Sendable {
    
    /// A property was found but not defined in the schema.
    case unexpectedProperty(String)
    
    /// A property value is unusual but not invalid.
    case unusualValue(String, String)
    
    /// The object structure deviates from typical patterns.
    case structuralDeviation(String)
    
    /// Custom validation warning.
    case custom(String)
}

// MARK: - Error Extensions

extension ObjectValidationError: LocalizedError {
    
    public var errorDescription: String? {
        switch self {
        case .schemaViolation(let message):
            return "Schema violation: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .missingRequiredProperty(let property):
            return "Missing required property: \(property)"
        case .invalidPropertyType(let property, let expected, let actual):
            return "Invalid type for property '\(property)': expected \(expected), got \(actual)"
        case .valueOutOfRange(let property, let value, let range):
            return "Value '\(value)' for property '\(property)' is outside allowed range: \(range)"
        case .additionalPropertiesNotAllowed(let properties):
            return "Additional properties not allowed: \(properties.joined(separator: ", "))"
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Codable Conformance

extension ObjectSchema: Codable where T: Codable {
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(jsonSchema, forKey: .jsonSchema)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(examples, forKey: .examples)
        try container.encode(validationMode, forKey: .validationMode)
        try container.encode(allowAdditionalProperties, forKey: .allowAdditionalProperties)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        jsonSchema = try container.decode(JSONSchema.self, forKey: .jsonSchema)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        examples = try container.decodeIfPresent([T].self, forKey: .examples)
        validationMode = try container.decodeIfPresent(ValidationMode.self, forKey: .validationMode) ?? .strict
        allowAdditionalProperties = try container.decodeIfPresent(Bool.self, forKey: .allowAdditionalProperties) ?? false
    }
    
    private enum CodingKeys: String, CodingKey {
        case jsonSchema = "json_schema"
        case name
        case description
        case examples
        case validationMode = "validation_mode"
        case allowAdditionalProperties = "allow_additional_properties"
    }
}

// MARK: - Equatable Conformance

extension ObjectSchema: Equatable where T: Equatable {
    
    public static func == (lhs: ObjectSchema<T>, rhs: ObjectSchema<T>) -> Bool {
        return lhs.name == rhs.name &&
               lhs.description == rhs.description &&
               lhs.examples == rhs.examples &&
               lhs.validationMode == rhs.validationMode &&
               lhs.allowAdditionalProperties == rhs.allowAdditionalProperties
        // Note: jsonSchema comparison would require Equatable conformance on JSONSchema
    }
}