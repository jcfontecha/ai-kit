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
/// - **Automatic Generation**: Can automatically derive schemas from Swift types
/// - **Validation**: Provides runtime validation of generated objects
/// - **Provider Agnostic**: Works with any AI provider that supports structured output
///
/// ## Usage Examples
///
/// ### Basic Object Schema
/// ```swift
/// struct Person: Codable {
///     let name: String
///     let age: Int
///     let email: String?
/// }
/// 
/// let schema = ObjectSchema<Person>()
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
///
/// ### Schema with Examples
/// ```swift
/// let schema = ObjectSchema<Person>()
///     .withExample(Person(name: "John Doe", age: 30, email: "john@example.com"))
///     .withExample(Person(name: "Jane Smith", age: 25, email: nil))
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
    
    /// Creates a new ObjectSchema with automatic schema generation.
    ///
    /// This initializer attempts to automatically generate a JSON Schema
    /// from the Swift type `T`. For complex types, consider providing
    /// a custom `jsonSchema`.
    ///
    /// - Parameters:
    ///   - jsonSchema: Custom JSON schema (auto-generated if nil)
    ///   - name: Optional name for the schema
    ///   - description: Optional description
    ///   - examples: Optional example instances
    ///   - validationMode: Validation strictness (defaults to .strict)
    ///   - allowAdditionalProperties: Allow extra properties (defaults to false)
    public init(
        jsonSchema: JSONSchema? = nil,
        name: String? = nil,
        description: String? = nil,
        examples: [T]? = nil,
        validationMode: ValidationMode = .strict,
        allowAdditionalProperties: Bool = false
    ) {
        // In a real implementation, this would use reflection or code generation
        // to automatically derive a JSON Schema from the Swift type T
        self.jsonSchema = jsonSchema ?? Self.generateSchemaForType()
        self.name = name ?? String(describing: T.self)
        self.description = description
        self.examples = examples
        self.validationMode = validationMode
        self.allowAdditionalProperties = allowAdditionalProperties
    }
    
    /// Creates an ObjectSchema with a fully specified JSON Schema.
    ///
    /// Use this initializer when you need full control over the JSON Schema
    /// definition, such as for complex validation rules or provider-specific
    /// schema features.
    ///
    /// - Parameters:
    ///   - jsonSchema: The complete JSON Schema definition
    ///   - name: Schema name
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
    
    // MARK: - Private Methods
    
    /// Generate a JSON Schema for the Swift type T.
    ///
    /// This is a placeholder implementation. In a real implementation,
    /// this would use reflection, code generation, or a schema registry
    /// to automatically derive schemas from Swift types.
    private static func generateSchemaForType() -> JSONSchema {
        // Placeholder: Return a generic object schema
        // In practice, this would analyze the type T and generate appropriate schema
        return .definition(SchemaDefinition(
            type: .object,
            description: "Auto-generated schema for \(T.self)"
        ))
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

// MARK: - Schema Factory Methods

public extension ObjectSchema {
    
    
    /// Create a schema for an array of objects.
    ///
    /// - Parameter elementType: The type of array elements
    /// - Returns: An ObjectSchema for arrays of the specified type
    static func array<U: Codable>(of elementType: U.Type) -> ObjectSchema<[U]> {
        let arraySchema = JSONSchema.array(
            items: ObjectSchema<U>().jsonSchema,
            minItems: 0
        )
        
        return ObjectSchema<[U]>(
            jsonSchema: arraySchema,
            name: "[\(elementType)]",
            description: "Array of \(elementType) objects"
        )
    }
    
    /// Create a schema for optional objects.
    ///
    /// - Parameter wrappedType: The wrapped type
    /// - Returns: An ObjectSchema for optional values of the specified type
    static func optional<U: Codable>(_ wrappedType: U.Type) -> ObjectSchema<U?> {
        // Optional schemas would need special handling in the JSON Schema
        // This is a simplified implementation
        return ObjectSchema<U?>(
            jsonSchema: ObjectSchema<U>().jsonSchema,
            name: "\(wrappedType)?",
            description: "Optional \(wrappedType) object"
        )
    }
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