import Foundation

// MARK: - Macro Declarations

/// A macro that automatically generates SchemaProviding conformance for a type.
/// 
/// This macro:
/// 1. Adds SchemaProviding conformance
/// 2. Generates a static schema property based on the type's properties
/// 3. Creates a Partial nested type for streaming support
/// 
/// Example usage:
/// ```swift
/// @AIModel
/// struct Recipe {
///     let title: String // Field("Creative recipe name")
///     let ingredients: [String] // Field("List of ingredients", maxItems: 20)
///     let servings: Int // Field("Number of servings", range: 1...10)
/// }
/// ```
@attached(extension, conformances: SchemaProviding)
@attached(member, names: named(schema), named(Partial))
public macro AIModel() = #externalMacro(
    module: "AIKitMacros",
    type: "AIModelMacro"
)

/// A macro for annotating model properties with descriptions and constraints.
///
/// Use @Field to provide metadata that will be used when generating the schema.
///
/// Example usage:
/// ```swift
/// @AIModel
/// struct Product {
///     @Field("Product name", minLength: 1, maxLength: 100)
///     let name: String
///     
///     @Field("Price in USD", range: 0.01...99999.99)
///     let price: Double
///     
///     @Field("Product tags", maxItems: 10)
///     let tags: [String]
/// }
/// ```
@attached(peer)
public macro Field(
    _ description: String,
    minLength: Int? = nil,
    maxLength: Int? = nil,
    pattern: String? = nil,
    range: ClosedRange<Double>? = nil,
    enum values: [String]? = nil,
    maxItems: Int? = nil,
    format: String? = nil
) = #externalMacro(
    module: "AIKitMacros",
    type: "FieldMacro"
)

// MARK: - Field Status for Partial Types

/// Status of a field during partial generation
public enum FieldStatus {
    case notStarted
    case inProgress
    case completed
    
    public var symbol: String {
        switch self {
        case .notStarted: return "⏳"
        case .inProgress: return "⚡"
        case .completed: return "✅"
        }
    }
}