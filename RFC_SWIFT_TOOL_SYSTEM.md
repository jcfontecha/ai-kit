# RFC: Swift-First Tool System for AIKit

**RFC Number**: 001  
**Status**: Draft  
**Author**: AIKit Team  
**Created**: 2025-01-01  

## Summary

This RFC proposes enhancements to AIKit's tool system to make it more Swift-native, type-safe, and developer-friendly. The proposal introduces a protocol-based approach with result builders, property wrappers, and compile-time schema generation.

## Motivation

While AIKit already has a functional tool system, there's an opportunity to make it feel more native to Swift developers by:

1. Leveraging Swift's type system for compile-time guarantees
2. Using result builders for declarative schema definition
3. Providing property wrappers for common patterns
4. Supporting actor isolation for thread-safe tool execution
5. Offering SwiftUI integration for interactive tools

## Detailed Design

### Core Tool Protocol

```swift
/// A type-safe, Swift-first protocol for AI tool definitions
public protocol AITool {
    /// The input type for this tool
    associatedtype Input: Codable
    
    /// The output type for this tool
    associatedtype Output: Codable
    
    /// Unique identifier for this tool
    static var name: String { get }
    
    /// Human-readable description for the AI model
    static var description: String { get }
    
    /// Execute the tool with the given input
    func execute(_ input: Input) async throws -> Output
}

/// Default implementation using type name
extension AITool {
    public static var name: String {
        String(describing: Self.self)
            .replacingOccurrences(of: "Tool", with: "")
            .camelCaseToSnakeCase()
    }
}
```

### Schema Generation with Result Builders

```swift
/// Result builder for declarative schema construction
@resultBuilder
public struct SchemaBuilder {
    public static func buildBlock<T>(_ components: SchemaProperty<T>...) -> Schema<T> {
        Schema(properties: components)
    }
    
    public static func buildOptional<T>(_ component: SchemaProperty<T>?) -> Schema<T> {
        Schema(properties: component.map { [$0] } ?? [])
    }
    
    public static func buildEither<T>(first component: SchemaProperty<T>) -> Schema<T> {
        Schema(properties: [component])
    }
    
    public static func buildEither<T>(second component: SchemaProperty<T>) -> Schema<T> {
        Schema(properties: [component])
    }
}

/// Schema definition with property constraints
public struct Schema<T: Codable> {
    let properties: [SchemaProperty<T>]
    
    public init(@SchemaBuilder _ builder: () -> Schema<T>) {
        self = builder()
    }
    
    init(properties: [SchemaProperty<T>]) {
        self.properties = properties
    }
}

/// Individual property definition
public struct SchemaProperty<T> {
    let keyPath: PartialKeyPath<T>
    let description: String?
    let constraints: [Constraint]
    
    public enum Constraint {
        case required
        case optional
        case minLength(Int)
        case maxLength(Int)
        case minimum(Double)
        case maximum(Double)
        case pattern(String)
        case enumValues([String])
    }
}
```

### Property Wrapper for Schema Definition

```swift
/// Property wrapper for schema-aware properties
@propertyWrapper
public struct SchemaField<Value: Codable> {
    public var wrappedValue: Value
    public let description: String?
    public let constraints: [SchemaProperty<Value>.Constraint]
    
    public init(
        wrappedValue: Value,
        description: String? = nil,
        constraints: SchemaProperty<Value>.Constraint...
    ) {
        self.wrappedValue = wrappedValue
        self.description = description
        self.constraints = constraints
    }
}

/// Example usage
struct WeatherInput: Codable {
    @SchemaField(description: "City name or coordinates", constraints: .required)
    var location: String
    
    @SchemaField(
        description: "Temperature units",
        constraints: .enumValues(["celsius", "fahrenheit"])
    )
    var units: String = "celsius"
}
```

### Tool Implementation Examples

```swift
/// Simple tool with automatic schema inference
struct WeatherTool: AITool {
    static let description = "Get current weather for a location"
    
    struct Input: Codable {
        @SchemaField(description: "City name or coordinates")
        let location: String
        
        @SchemaField(description: "Temperature units")
        let units: String
    }
    
    struct Output: Codable {
        let temperature: Double
        let condition: String
        let humidity: Int
        let windSpeed: Double
    }
    
    func execute(_ input: Input) async throws -> Output {
        // Implementation using weather API
        let weatherData = try await WeatherAPI.fetch(
            location: input.location,
            units: input.units
        )
        
        return Output(
            temperature: weatherData.temp,
            condition: weatherData.condition,
            humidity: weatherData.humidity,
            windSpeed: weatherData.wind
        )
    }
}

/// Tool with custom schema using result builder
struct CalculatorTool: AITool {
    static let description = "Perform mathematical calculations"
    
    struct Input: Codable {
        let expression: String
        let precision: Int?
    }
    
    typealias Output = Double
    
    static var schema: Schema<Input> {
        Schema {
            Property(\.expression, description: "Mathematical expression to evaluate")
                .required()
                .minLength(1)
            
            Property(\.precision, description: "Decimal places for result")
                .optional()
                .minimum(0)
                .maximum(10)
        }
    }
    
    func execute(_ input: Input) async throws -> Output {
        let calculator = ExpressionCalculator()
        let result = try calculator.evaluate(input.expression)
        
        if let precision = input.precision {
            return round(result * pow(10, Double(precision))) / pow(10, Double(precision))
        }
        
        return result
    }
}
```

### Actor-Isolated Tools

```swift
/// Actor for thread-safe tool execution
@ToolActor
actor DatabaseQueryTool: AITool {
    static let description = "Query the application database"
    
    private let database: Database
    
    init(database: Database) {
        self.database = database
    }
    
    struct Input: Codable {
        let query: String
        let parameters: [String: String]?
    }
    
    typealias Output = [DatabaseRecord]
    
    func execute(_ input: Input) async throws -> Output {
        // Thread-safe database access
        return try await database.execute(
            query: input.query,
            parameters: input.parameters ?? [:]
        )
    }
}

/// Global actor for tool execution
@globalActor
public actor ToolActor {
    public static let shared = ToolActor()
}
```

### Interactive Tools with SwiftUI

```swift
/// Protocol for tools requiring user interaction
public protocol InteractiveTool: AITool {
    associatedtype InteractionView: View
    
    /// Create the interaction view for user input
    func createInteractionView(
        input: Input,
        completion: @escaping (Result<Output, Error>) -> Void
    ) -> InteractionView
}

/// Example interactive tool
struct ConfirmationTool: InteractiveTool {
    static let description = "Request user confirmation"
    
    struct Input: Codable {
        let message: String
        let destructive: Bool
    }
    
    struct Output: Codable {
        let confirmed: Bool
        let timestamp: Date
    }
    
    func execute(_ input: Input) async throws -> Output {
        // This won't be called for interactive tools
        fatalError("Interactive tools must use createInteractionView")
    }
    
    func createInteractionView(
        input: Input,
        completion: @escaping (Result<Output, Error>) -> Void
    ) -> some View {
        ConfirmationView(
            message: input.message,
            isDestructive: input.destructive,
            onConfirm: {
                completion(.success(Output(
                    confirmed: true,
                    timestamp: Date()
                )))
            },
            onCancel: {
                completion(.success(Output(
                    confirmed: false,
                    timestamp: Date()
                )))
            }
        )
    }
}

struct ConfirmationView: View {
    let message: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                
                Button("Confirm", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(isDestructive ? .red : .accentColor)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
}
```

### Tool Registry and Discovery

```swift
/// Registry for managing available tools
public actor ToolRegistry {
    private var tools: [String: any AITool] = [:]
    
    /// Register a tool
    public func register<T: AITool>(_ tool: T) {
        tools[T.name] = tool
    }
    
    /// Register multiple tools
    public func register<each T: AITool>(_ tool: repeat each T) {
        repeat tools[(each T).name] = each tool
    }
    
    /// Get all registered tools
    public func allTools() -> [Tool] {
        tools.values.map { tool in
            Tool(
                name: type(of: tool).name,
                description: type(of: tool).description,
                inputSchema: generateSchema(for: type(of: tool).Input.self),
                execute: tool.execute
            )
        }
    }
}
```

### Integration with Existing AIKit

```swift
extension AIClient {
    /// Execute a generation with Swift-native tools
    public func generateText<each T: AITool>(
        _ model: LanguageModel,
        messages: [CoreMessage],
        tools: repeat each T,
        maxSteps: Int = 1
    ) async throws -> TextResponse {
        // Convert Swift tools to existing Tool type
        let legacyTools = [Tool]() // Convert each tool
        
        // Use existing generateText with converted tools
        return try await generateText(
            model,
            messages: messages,
            tools: legacyTools,
            maxSteps: maxSteps
        )
    }
}

extension Tool {
    /// Create from Swift-native AITool
    public init<T: AITool>(from tool: T) {
        self.init(
            name: T.name,
            description: T.description,
            inputSchema: T.generateSchema(),
            execute: { input in
                let typedInput = try JSONDecoder().decode(T.Input.self, from: input)
                let output = try await tool.execute(typedInput)
                return try JSONEncoder().encode(output)
            }
        )
    }
}
```

## Migration Path

### Phase 1: Parallel Implementation
- Implement new protocol alongside existing Tool struct
- Provide converters between old and new formats
- No breaking changes

### Phase 2: Adoption
- Update examples to use new system
- Provide migration guide
- Deprecate old patterns

### Phase 3: Full Migration
- Make new system the default
- Keep legacy support for compatibility

## Example Usage

```swift
// Define tools
let weatherTool = WeatherTool()
let calculatorTool = CalculatorTool()
let confirmationTool = ConfirmationTool()

// Register with AIClient
let response = try await client.generateText(
    model,
    messages: messages,
    tools: weatherTool, calculatorTool, confirmationTool,
    maxSteps: 3
)

// Handle interactive tools in UI
if let toolCall = response.pendingToolCall,
   toolCall.name == ConfirmationTool.name {
    let input = try JSONDecoder().decode(
        ConfirmationTool.Input.self,
        from: toolCall.arguments
    )
    
    ConfirmationSheet(
        tool: confirmationTool,
        input: input
    ) { result in
        // Handle result
    }
}
```

## Benefits

1. **Type Safety**: Compile-time guarantees for tool inputs/outputs
2. **Swift Native**: Uses language features like result builders and property wrappers
3. **Declarative**: Clear, readable schema definitions
4. **Thread Safe**: Actor isolation for concurrent execution
5. **UI Integration**: First-class support for interactive tools
6. **Discoverable**: Tools are self-documenting with schemas

## Alternatives Considered

1. **Macro-based Generation**: Using Swift macros for schema generation
   - Pros: More automatic
   - Cons: Less flexible, requires macro support

2. **Protocol Witnesses**: Using protocol witnesses for tool definitions
   - Pros: More functional
   - Cons: Less familiar to Swift developers

3. **Codable-only**: Relying purely on Codable for schemas
   - Pros: Simpler
   - Cons: Less expressive, no constraints

## Future Directions

1. **Tool Composition**: Combining multiple tools into workflows
2. **Tool Versioning**: Supporting multiple versions of tools
3. **Tool Marketplace**: Sharing tools between projects
4. **Visual Tool Builder**: SwiftUI app for creating tools
5. **Tool Testing**: Specialized testing utilities for tools

## Conclusion

This Swift-first tool system would make AIKit feel more native to iOS developers while providing powerful capabilities for building AI-powered applications. The design leverages Swift's strengths while maintaining compatibility with the existing system.