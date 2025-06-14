# Swift AI SDK - Elegant API Design

## Design Philosophy

This Swift AI SDK combines the power and versatility of Vercel's AI SDK with the elegance and patterns beloved by iOS/macOS developers. The design prioritizes:

- **Protocol-Oriented Programming**: Heavy use of protocols for extensibility and testability
- **Composition over Inheritance**: Flexible architecture through composition
- **Swift Concurrency**: Native async/await and AsyncSequence support
- **Type Safety**: Leverage Swift's type system for compile-time guarantees
- **Familiar Patterns**: Builder patterns, Result types, and SwiftUI-like configuration
- **No Global Functions**: Everything is namespaced and organized

## Core Protocol Hierarchy

### 1. Provider Protocol - Main Entry Point

```swift
// Protocol for AI providers (OpenAI, Anthropic, etc.)
// This is the main abstraction users interact with
public protocol AIProvider: Sendable {
    var name: String { get }
    var supportedModels: Set<String> { get }
    
    init(apiKey: String, middleware: [any AIMiddleware])
    
    func model(_ modelId: String, configuration: ModelConfiguration) throws -> LanguageModel
    func validateConfiguration(_ configuration: ModelConfiguration) throws
}
```

### 2. Language Model Protocol - Primary API Surface

```swift
// Core protocol that all language models must implement
// This is what users call methods on - middleware is always applied internally
public protocol LanguageModel: Sendable {
    var id: String { get }
    var provider: String { get }
    var maxTokens: Int? { get }
    var supportsStreaming: Bool { get }
    var supportsToolCalling: Bool { get }
    var supportsImageInput: Bool { get }
    
    // Core generation methods with full request objects
    func generateText(_ request: TextGenerationRequest) async throws -> TextGenerationResponse
    func generateObject<T: Codable>(_ request: ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T>
    
    // Streaming methods with full request objects
    func streamText(_ request: TextGenerationRequest) -> AsyncThrowingStream<TextChunk, Error>
    func streamObject<T: Codable>(_ request: ObjectGenerationRequest<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error>
}

extension LanguageModel {
    // Default implementations for optional features
    public var maxTokens: Int? { nil }
    public var supportsStreaming: Bool { true }
    public var supportsToolCalling: Bool { false }
    public var supportsImageInput: Bool { false }
}

// MARK: - Convenience Methods for Better Ergonomics

extension LanguageModel {
    // MARK: - Text Generation Convenience Methods
    
    // Simple string input
    public func generateText(
        _ message: String,
        role: Role = .user,
        tools: [any AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> TextGenerationResponse {
        let messages = [Message(role: role, content: [.text(message)])]
        let request = TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try await generateText(request)
    }
    
    // Message array input
    public func generateText(
        _ messages: [Message],
        tools: [any AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> TextGenerationResponse {
        let request = TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try await generateText(request)
    }
    
    // Conversation builder input
    public func generateText(
        tools: [any AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        @ConversationBuilder _ conversation: () -> [Message]
    ) async throws -> TextGenerationResponse {
        let request = TextGenerationRequest(
            messages: conversation(),
            tools: tools,
            toolChoice: toolChoice,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try await generateText(request)
    }
    
    // MARK: - Object Generation Convenience Methods
    
    // Simple string input with type inference
    public func generateObject<T: Codable>(
        _ message: String,
        as type: T.Type,
        mode: ObjectGenerationMode = .auto,
        validator: ((T) throws -> Void)? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> ObjectGenerationResponse<T> {
        let messages = [Message.user(message)]
        let schema = ObjectSchema(type: type, validator: validator)
        let request = ObjectGenerationRequest(
            messages: messages,
            schema: schema,
            mode: mode,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try await generateObject(request)
    }
    
    // Message array input
    public func generateObject<T: Codable>(
        _ messages: [Message],
        schema: ObjectSchema<T>,
        mode: ObjectGenerationMode = .auto,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> ObjectGenerationResponse<T> {
        let request = ObjectGenerationRequest(
            messages: messages,
            schema: schema,
            mode: mode,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return try await generateObject(request)
    }
    
    // MARK: - Streaming Text Convenience Methods
    
    // Simple string input
    public func streamText(
        _ message: String,
        tools: [any AITool]? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<TextChunk, Error> {
        let messages = [Message.user(message)]
        let request = TextGenerationRequest(
            messages: messages,
            tools: tools,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return streamText(request)
    }
    
    // Message array input  
    public func streamText(
        _ messages: [Message],
        tools: [any AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<TextChunk, Error> {
        let request = TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return streamText(request)
    }
    
    // MARK: - Streaming Object Convenience Methods
    
    // Simple string input with automatic JSON completion
    public func streamObject<T: Codable>(
        _ message: String,
        as type: T.Type,
        mode: ObjectGenerationMode = .auto,
        validator: ((T) throws -> Void)? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        let messages = [Message.user(message)]
        let schema = ObjectSchema(type: type, validator: validator)
        let request = ObjectGenerationRequest(
            messages: messages,
            schema: schema,
            mode: mode,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return streamObject(request)
    }
    
    // Message array input with automatic JSON completion
    public func streamObject<T: Codable>(
        _ messages: [Message],
        schema: ObjectSchema<T>,
        mode: ObjectGenerationMode = .auto,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        let request = ObjectGenerationRequest(
            messages: messages,
            schema: schema,
            mode: mode,
            maxTokens: maxTokens,
            temperature: temperature
        )
        return streamObject(request)
    }
}

// Model configuration using builder pattern
public struct ModelConfiguration: Sendable {
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let seed: Int?
    public let stopSequences: [String]?
    
    public init() {
        self.temperature = nil
        self.maxTokens = nil
        self.topP = nil
        self.presencePenalty = nil
        self.frequencyPenalty = nil
        self.seed = nil
        self.stopSequences = nil
    }
    
    // Builder pattern methods
    public func temperature(_ value: Double) -> ModelConfiguration {
        ModelConfiguration(
            temperature: value,
            maxTokens: maxTokens,
            topP: topP,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            stopSequences: stopSequences
        )
    }
    
    public func maxTokens(_ value: Int) -> ModelConfiguration {
        ModelConfiguration(
            temperature: temperature,
            maxTokens: value,
            topP: topP,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            seed: seed,
            stopSequences: stopSequences
        )
    }
    
    // ... other builder methods
}
```

### 3. Tool Protocol

```swift
// Protocol for defining AI tools
public protocol AITool: Sendable {
    associatedtype Parameters: Codable
    associatedtype Result: Codable
    
    var name: String { get }
    var description: String { get }
    var parameters: JSONSchema { get }
    
    func execute(_ parameters: Parameters) async throws -> Result
}

// JSON Schema representation for tool parameters with enhanced enum support
public struct JSONSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: JSONSchema]?
    public let required: [String]?
    public let description: String?
    public let items: JSONSchema?
    public let enumValues: [JSONSchemaValue]?
    
    // Codable key mapping for JSON serialization
    private enum CodingKeys: String, CodingKey {
        case type, properties, required, description, items
        case enumValues = "enum"
    }
    
    // Enum value wrapper that supports multiple types
    public enum JSONSchemaValue: Codable, Sendable {
        case string(String)
        case integer(Int)
        case number(Double)
        case boolean(Bool)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else if let intValue = try? container.decode(Int.self) {
                self = .integer(intValue)
            } else if let doubleValue = try? container.decode(Double.self) {
                self = .number(doubleValue)
            } else if let boolValue = try? container.decode(Bool.self) {
                self = .boolean(boolValue)
            } else {
                throw DecodingError.typeMismatch(JSONSchemaValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string, integer, number, or boolean"))
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
            }
        }
    }
    
    // Convenience initializers for common types
    public static func string(description: String? = nil, enum: [String]? = nil) -> JSONSchema {
        JSONSchema(
            type: "string",
            properties: nil,
            required: nil,
            description: description,
            items: nil,
            enumValues: enum?.map { .string($0) }
        )
    }
    
    public static func integer(description: String? = nil, enum: [Int]? = nil) -> JSONSchema {
        JSONSchema(
            type: "integer",
            properties: nil,
            required: nil,
            description: description,
            items: nil,
            enumValues: enum?.map { .integer($0) }
        )
    }
    
    public static func number(description: String? = nil, enum: [Double]? = nil) -> JSONSchema {
        JSONSchema(
            type: "number",
            properties: nil,
            required: nil,
            description: description,
            items: nil,
            enumValues: enum?.map { .number($0) }
        )
    }
    
    public static func boolean(description: String? = nil) -> JSONSchema {
        JSONSchema(
            type: "boolean",
            properties: nil,
            required: nil,
            description: description,
            items: nil,
            enumValues: nil
        )
    }
    
    public static func array(items: JSONSchema, description: String? = nil) -> JSONSchema {
        JSONSchema(
            type: "array",
            properties: nil,
            required: nil,
            description: description,
            items: items,
            enumValues: nil
        )
    }
    
    public static func object(properties: [String: JSONSchema], required: [String] = [], description: String? = nil) -> JSONSchema {
        JSONSchema(
            type: "object",
            properties: properties,
            required: required,
            description: description,
            items: nil,
            enumValues: nil
        )
    }
}
```

## Provider Implementation

```swift
// Example provider implementation showing middleware integration
public struct OpenAIProvider: AIProvider {
    public let name = "OpenAI"
    public let supportedModels: Set<String> = [
        "gpt-4", "gpt-4-turbo", "gpt-3.5-turbo", "gpt-4o"
    ]
    
    private let apiKey: String
    private let middleware: [any AIMiddleware]
    
    public init(apiKey: String, middleware: [any AIMiddleware] = []) {
        self.apiKey = apiKey
        self.middleware = middleware
    }
    
    public func model(_ modelId: String, configuration: ModelConfiguration = ModelConfiguration()) throws -> LanguageModel {
        guard supportedModels.contains(modelId) else {
            throw AIError.modelNotFound(modelId)
        }
        
        try validateConfiguration(configuration)
        
        // Create the raw OpenAI model
        let rawModel = OpenAILanguageModel(
            id: modelId,
            apiKey: apiKey,
            configuration: configuration
        )
        
        // Wrap with middleware if any are provided
        if middleware.isEmpty {
            return rawModel
        } else {
            return MiddlewareWrappedModel(
                underlyingModel: rawModel,
                middleware: middleware
            )
        }
    }
    
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        if let temperature = configuration.temperature {
            guard temperature >= 0.0 && temperature <= 2.0 else {
                throw AIError.invalidConfiguration("Temperature must be between 0.0 and 2.0")
            }
        }
        
        if let maxTokens = configuration.maxTokens {
            guard maxTokens > 0 && maxTokens <= 4096 else {
                throw AIError.invalidConfiguration("Max tokens must be between 1 and 4096")
            }
        }
    }
}

// Internal middleware wrapper that users never see directly
internal class MiddlewareWrappedModel: LanguageModel {
    private let underlyingModel: LanguageModel
    private let middleware: [any AIMiddleware]
    
    // Delegate properties to underlying model
    var id: String { underlyingModel.id }
    var provider: String { underlyingModel.provider }
    var maxTokens: Int? { underlyingModel.maxTokens }
    var supportsStreaming: Bool { underlyingModel.supportsStreaming }
    var supportsToolCalling: Bool { underlyingModel.supportsToolCalling }
    var supportsImageInput: Bool { underlyingModel.supportsImageInput }
    
    init(underlyingModel: LanguageModel, middleware: [any AIMiddleware]) {
        self.underlyingModel = underlyingModel
        self.middleware = middleware
    }
    
    // Apply middleware chain to text generation
    func generateText(_ request: TextGenerationRequest) async throws -> TextGenerationResponse {
        let result = try await executeMiddlewareChain(request: request) { req in
            try await self.underlyingModel.generateText(req)
        }
        return result as! TextGenerationResponse
    }
    
    // Apply middleware chain to object generation
    func generateObject<T: Codable>(_ request: ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T> {
        let result = try await executeMiddlewareChain(request: request) { req in
            try await self.underlyingModel.generateObject(req)
        }
        return result as! ObjectGenerationResponse<T>
    }
    
    // Streaming methods delegate directly (middleware for streams is more complex)
    func streamText(_ request: TextGenerationRequest) -> AsyncThrowingStream<TextChunk, Error> {
        // For now, delegate directly - streaming middleware could be added later
        return underlyingModel.streamText(request)
    }
    
    func streamObject<T: Codable>(_ request: ObjectGenerationRequest<T>) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        // JSON completion is applied automatically inside the implementation
        return underlyingModel.streamObject(request)
    }
    
    // Execute middleware chain
    private func executeMiddlewareChain<T>(
        request: T,
        operation: @escaping (T) async throws -> any Sendable
    ) async throws -> any Sendable {
        guard !middleware.isEmpty else {
            return try await operation(request)
        }
        
        // Create middleware chain by reducing from right to left
        var chain = operation
        
        for middleware in middleware.reversed() {
            let currentChain = chain
            chain = { req in
                try await middleware.process(request: req, next: currentChain)
            }
        }
        
        return try await chain(request)
    }
}
```

## Request and Response Types

```swift
// Text generation request
public struct TextGenerationRequest: Sendable {
    public let messages: [Message]
    public let tools: [any AITool]?
    public let toolChoice: ToolChoice?
    public let maxTokens: Int?
    public let temperature: Double?
    public let topP: Double?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let seed: Int?
    public let stopSequences: [String]?
    
    public init(
        messages: [Message],
        tools: [any AITool]? = nil,
        toolChoice: ToolChoice? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        seed: Int? = nil,
        stopSequences: [String]? = nil
    ) {
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.seed = seed
        self.stopSequences = stopSequences
    }
}

// Object generation request with generic type
public struct ObjectGenerationRequest<T: Codable>: Sendable {
    public let messages: [Message]
    public let schema: ObjectSchema<T>
    public let mode: ObjectGenerationMode
    public let maxTokens: Int?
    public let temperature: Double?
    
    public init(
        messages: [Message],
        schema: ObjectSchema<T>,
        mode: ObjectGenerationMode = .auto,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) {
        self.messages = messages
        self.schema = schema
        self.mode = mode
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

// Object schema with validation
public struct ObjectSchema<T: Codable>: Sendable {
    public let type: T.Type
    public let jsonSchema: JSONSchema
    public let validator: ((T) throws -> Void)?
    
    public init(
        type: T.Type,
        jsonSchema: JSONSchema,
        validator: ((T) throws -> Void)? = nil
    ) {
        self.type = type
        self.jsonSchema = jsonSchema
        self.validator = validator
    }
    
    // Convenience initializer that derives schema from Codable type
    public init(type: T.Type, validator: ((T) throws -> Void)? = nil) {
        self.type = type
        self.jsonSchema = JSONSchema.fromCodable(type)
        self.validator = validator
    }
}

public enum ObjectGenerationMode: String, Sendable, CaseIterable {
    case auto = "auto"
    case json = "json"
    case tool = "tool"
}

// Response types
public struct TextGenerationResponse: Sendable {
    public let text: String
    public let finishReason: FinishReason
    public let usage: TokenUsage
    public let toolCalls: [ToolCall]?
    public let rawResponse: [String: Any]?
}

public struct ObjectGenerationResponse<T: Codable>: Sendable {
    public let object: T
    public let finishReason: FinishReason
    public let usage: TokenUsage
    public let rawResponse: [String: Any]?
}

public enum FinishReason: String, Sendable, CaseIterable {
    case stop = "stop"
    case length = "length"
    case contentFilter = "content_filter"
    case toolCalls = "tool_calls"
    case error = "error"
    case other = "other"
}

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}
```

## Message Types

```swift
// Multi-modal message system
public struct Message: Sendable, Codable {
    public let role: Role
    public let content: [MessageContent]
    public let name: String?
    public let toolCallId: String?
    
    public init(
        role: Role,
        content: [MessageContent],
        name: String? = nil,
        toolCallId: String? = nil
    ) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCallId = toolCallId
    }
    
    // Convenience initializers
    public static func system(_ text: String) -> Message {
        Message(role: .system, content: [.text(text)])
    }
    
    public static func user(_ text: String) -> Message {
        Message(role: .user, content: [.text(text)])
    }
    
    public static func assistant(_ text: String) -> Message {
        Message(role: .assistant, content: [.text(text)])
    }
    
    public static func user(text: String, images: [MessageImage]) -> Message {
        var content: [MessageContent] = [.text(text)]
        content.append(contentsOf: images.map { .image($0) })
        return Message(role: .user, content: content)
    }
}

public enum Role: String, Sendable, Codable, CaseIterable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
    case tool = "tool"
}

public enum MessageContent: Sendable, Codable {
    case text(String)
    case image(MessageImage)
    case file(MessageFile)
    
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }
    
    public var image: MessageImage? {
        if case .image(let image) = self { return image }
        return nil
    }
    
    public var file: MessageFile? {
        if case .file(let file) = self { return file }
        return nil
    }
}

public struct MessageImage: Sendable, Codable {
    public let url: String?
    public let data: Data?
    public let mimeType: String
    
    public init(url: String, mimeType: String = "image/jpeg") {
        self.url = url
        self.data = nil
        self.mimeType = mimeType
    }
    
    public init(data: Data, mimeType: String) {
        self.url = nil
        self.data = data
        self.mimeType = mimeType
    }
}

public struct MessageFile: Sendable, Codable {
    public let name: String
    public let data: Data
    public let mimeType: String
    
    public init(name: String, data: Data, mimeType: String) {
        self.name = name
        self.data = data
        self.mimeType = mimeType
    }
}
```

## Tool System

```swift
// Tool choice options
public enum ToolChoice: Sendable, Codable {
    case auto
    case none
    case required
    case specific(String)
    
    public var value: String {
        switch self {
        case .auto: return "auto"
        case .none: return "none"
        case .required: return "required"
        case .specific(let name): return name
        }
    }
}

// Tool call representation
public struct ToolCall: Sendable, Codable {
    public let id: String
    public let name: String
    public let arguments: [String: Any]
    
    public init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// Tool execution result
public struct ToolResult: Sendable, Codable {
    public let toolCallId: String
    public let result: Any
    public let error: String?
    
    public init(toolCallId: String, result: Any, error: String? = nil) {
        self.toolCallId = toolCallId
        self.result = result
        self.error = error
    }
}

// Example tool implementation
public struct WeatherTool: AITool {
    public typealias Parameters = WeatherParameters
    public typealias Result = WeatherResult
    
    public let name = "get_weather"
    public let description = "Get current weather information for a location"
    public let parameters = JSONSchema.object(
        properties: [
            "location": .string(description: "The city and state/country"),
            "unit": .string(description: "Temperature unit (celsius or fahrenheit)")
        ],
        required: ["location"]
    )
    
    public func execute(_ parameters: WeatherParameters) async throws -> WeatherResult {
        // Implementation would call weather API
        return WeatherResult(
            location: parameters.location,
            temperature: 22,
            unit: parameters.unit ?? "celsius",
            description: "Sunny"
        )
    }
}

public struct WeatherParameters: Codable {
    public let location: String
    public let unit: String?
}

public struct WeatherResult: Codable {
    public let location: String
    public let temperature: Double
    public let unit: String
    public let description: String
}
```

// MARK: - Conversation Builder

// SwiftUI-like conversation builder for elegant message composition
@resultBuilder
public struct ConversationBuilder {
    public static func buildBlock(_ messages: Message...) -> [Message] {
        Array(messages)
    }
    
    public static func buildArray(_ components: [[Message]]) -> [Message] {
        components.flatMap { $0 }
    }
    
    public static func buildOptional(_ component: [Message]?) -> [Message] {
        component ?? []
    }
    
    public static func buildEither(first component: [Message]) -> [Message] {
        component
    }
    
    public static func buildEither(second component: [Message]) -> [Message] {
        component
    }
}
```

## AsyncSequence-Based Streaming

```swift
// Streaming chunk types
public struct TextChunk: Sendable {
    public let delta: String
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    public let toolCalls: [ToolCall]?
    
    public init(
        delta: String,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil,
        toolCalls: [ToolCall]? = nil
    ) {
        self.delta = delta
        self.finishReason = finishReason
        self.usage = usage
        self.toolCalls = toolCalls
    }
}

public struct ObjectChunk<T: Codable>: Sendable {
    public let delta: String
    public let partialObject: T?
    public let finishedObject: T?
    public let finishReason: FinishReason?
    public let usage: TokenUsage?
    
    public init(
        delta: String,
        partialObject: T? = nil,
        finishedObject: T? = nil,
        finishReason: FinishReason? = nil,
        usage: TokenUsage? = nil
    ) {
        self.delta = delta
        self.partialObject = partialObject
        self.finishedObject = finishedObject
        self.finishReason = finishReason
        self.usage = usage
    }
}

// Stream helpers for common operations
extension AsyncThrowingStream where Element == TextChunk {
    // Collect all text chunks into a single string
    public func collectText() async throws -> String {
        var result = ""
        for try await chunk in self {
            result += chunk.delta
        }
        return result
    }
    
    // Get the final response with metadata
    public func collectResponse() async throws -> TextGenerationResponse {
        var text = ""
        var finishReason: FinishReason = .stop
        var usage: TokenUsage?
        var toolCalls: [ToolCall]?
        
        for try await chunk in self {
            text += chunk.delta
            if let reason = chunk.finishReason {
                finishReason = reason
            }
            if let chunkUsage = chunk.usage {
                usage = chunkUsage
            }
            if let calls = chunk.toolCalls {
                toolCalls = calls
            }
        }
        
        return TextGenerationResponse(
            text: text,
            finishReason: finishReason,
            usage: usage ?? TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0),
            toolCalls: toolCalls,
            rawResponse: nil
        )
    }
}

extension AsyncThrowingStream where Element: ObjectChunk<T> {
    // Collect the final object
    public func collectObject() async throws -> T {
        var finalObject: T?
        
        for try await chunk in self {
            if let finished = chunk.finishedObject {
                finalObject = finished
            }
        }
        
        guard let object = finalObject else {
            throw AIError.noObjectGenerated("Stream ended without producing a complete object")
        }
        
        return object
    }
    
    // Get the final response with metadata
    public func collectResponse() async throws -> ObjectGenerationResponse<T> {
        var finalObject: T?
        var finishReason: FinishReason = .stop
        var usage: TokenUsage?
        
        for try await chunk in self {
            if let finished = chunk.finishedObject {
                finalObject = finished
            }
            if let reason = chunk.finishReason {
                finishReason = reason
            }
            if let chunkUsage = chunk.usage {
                usage = chunkUsage
            }
        }
        
        guard let object = finalObject else {
            throw AIError.noObjectGenerated("Stream ended without producing a complete object")
        }
        
        return ObjectGenerationResponse(
            object: object,
            finishReason: finishReason,
            usage: usage ?? TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0),
            rawResponse: nil
        )
    }
}
```

## Schema Validation and Type Safety

```swift
// JSON Schema generation from Swift types
extension JSONSchema {
    // Automatically generate schema from Codable types
    public static func fromCodable<T: Codable>(_ type: T.Type) -> JSONSchema {
        let mirror = Mirror(reflecting: type.self)
        var properties: [String: JSONSchema] = [:]
        var required: [String] = []
        
        // This would be implemented using reflection or code generation
        // For now, showing the interface
        return JSONSchema.object(properties: properties, required: required)
    }
    
    // Validation helpers
    public func validate<T: Codable>(_ object: T) throws {
        // Implement validation logic based on schema
        let data = try JSONEncoder().encode(object)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try validateObject(json, against: self)
    }
    
    private func validateObject(_ object: [String: Any]?, against schema: JSONSchema) throws {
        // Implementation would validate object against schema
        // Including type checking, required fields, etc.
    }
}

// Custom validation attributes for enhanced type safety
@propertyWrapper
public struct Validated<T> {
    private var value: T
    private let validator: (T) throws -> Void
    
    public init(wrappedValue: T, _ validator: @escaping (T) throws -> Void) {
        self.value = wrappedValue
        self.validator = validator
        try! validator(wrappedValue) // Validate on initialization
    }
    
    public var wrappedValue: T {
        get { value }
        set {
            try! validator(newValue)
            value = newValue
        }
    }
}

// Example usage with validation
public struct UserProfile: Codable {
    @Validated({ email in
        guard email.contains("@") else {
            throw ValidationError.invalidEmail
        }
    })
    public var email: String
    
    @Validated({ age in
        guard age >= 0 && age <= 120 else {
            throw ValidationError.invalidAge
        }
    })
    public var age: Int
    
    public var name: String
}

// Schema builder for complex validation rules
public struct SchemaBuilder<T: Codable> {
    private var validationRules: [(T) throws -> Void] = []
    private let type: T.Type
    
    public init(type: T.Type) {
        self.type = type
    }
    
    public func validate(_ rule: @escaping (T) throws -> Void) -> SchemaBuilder<T> {
        var builder = self
        builder.validationRules.append(rule)
        return builder
    }
    
    public func build() -> ObjectSchema<T> {
        let combinedValidator: (T) throws -> Void = { object in
            for rule in self.validationRules {
                try rule(object)
            }
        }
        
        return ObjectSchema(
            type: type,
            jsonSchema: .fromCodable(type),
            validator: combinedValidator
        )
    }
}

// Convenience method for schema building
extension ObjectSchema {
    public static func build<T: Codable>(
        for type: T.Type,
        @ValidationBuilder _ validations: () -> [(T) throws -> Void]
    ) -> ObjectSchema<T> {
        let rules = validations()
        let combinedValidator: (T) throws -> Void = { object in
            for rule in rules {
                try rule(object)
            }
        }
        
        return ObjectSchema(
            type: type,
            jsonSchema: .fromCodable(type),
            validator: combinedValidator
        )
    }
}

@resultBuilder
public struct ValidationBuilder<T> {
    public static func buildBlock(_ validations: ((T) throws -> Void)...) -> [(T) throws -> Void] {
        Array(validations)
    }
}

// Validation errors
public enum ValidationError: Error, LocalizedError {
    case invalidEmail
    case invalidAge
    case missingRequiredField(String)
    case invalidValue(String, Any)
    
    public var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Invalid email format"
        case .invalidAge:
            return "Age must be between 0 and 120"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidValue(let field, let value):
            return "Invalid value for \(field): \(value)"
        }
    }
}
```

## Error Handling System

```swift
// Comprehensive error hierarchy following Swift conventions
public enum AIError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case noObjectGenerated(String)
    case apiCallFailed(underlying: Error, isRetryable: Bool)
    case invalidResponse(String)
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case authenticationFailed(String)
    case modelNotFound(String)
    case invalidInput(String)
    case streamingFailed(String)
    case toolExecutionFailed(toolName: String, error: Error)
    case validationFailed(ValidationError)
    case networkError(URLError)
    case decodingError(DecodingError)
    case timeout(TimeInterval)
    
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .noObjectGenerated(let message):
            return "No object generated: \(message)"
        case .apiCallFailed(let error, _):
            return "API call failed: \(error.localizedDescription)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .rateLimitExceeded(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limit exceeded. Retry after \(retryAfter) seconds"
            } else {
                return "Rate limit exceeded"
            }
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .modelNotFound(let model):
            return "Model not found: \(model)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .streamingFailed(let message):
            return "Streaming failed: \(message)"
        case .toolExecutionFailed(let toolName, let error):
            return "Tool '\(toolName)' execution failed: \(error.localizedDescription)"
        case .validationFailed(let validationError):
            return "Validation failed: \(validationError.localizedDescription)"
        case .networkError(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .decodingError(let decodingError):
            return "Decoding error: \(decodingError.localizedDescription)"
        case .timeout(let interval):
            return "Request timed out after \(interval) seconds"
        }
    }
    
    public var isRetryable: Bool {
        switch self {
        case .apiCallFailed(_, let retryable):
            return retryable
        case .rateLimitExceeded:
            return true
        case .networkError(let urlError):
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        case .timeout:
            return true
        default:
            return false
        }
    }
    
    public static func == (lhs: AIError, rhs: AIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidConfiguration(let l), .invalidConfiguration(let r)):
            return l == r
        case (.noObjectGenerated(let l), .noObjectGenerated(let r)):
            return l == r
        case (.invalidResponse(let l), .invalidResponse(let r)):
            return l == r
        // Add other cases as needed
        default:
            return false
        }
    }
}

// Result type extensions for AI operations
extension Result where Success == TextGenerationResponse, Failure == AIError {
    public var text: String? {
        switch self {
        case .success(let response):
            return response.text
        case .failure:
            return nil
        }
    }
    
    public var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}

// Retry mechanism with exponential backoff
public actor RetryManager {
    private let maxRetries: Int
    private let baseDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let jitter: Bool
    
    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        jitter: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }
    
    public func retry<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0...maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                // Check if error is retryable
                if let aiError = error as? AIError, !aiError.isRetryable {
                    throw error
                }
                
                // Don't delay on the last attempt
                guard attempt < maxRetries else { break }
                
                // Calculate delay with exponential backoff
                let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
                let jitteredDelay = jitter ? delay * (0.5 + Double.random(in: 0...0.5)) : delay
                
                try await Task.sleep(nanoseconds: UInt64(jitteredDelay * 1_000_000_000))
            }
        }
        
        throw lastError ?? AIError.invalidConfiguration("Unknown error in retry mechanism")
    }
}

// Extensions to AIClient for error handling
extension AIClient {
    // Generate text with automatic retry
    public func generateTextWithRetry(
        _ messages: [Message],
        retryManager: RetryManager = RetryManager(),
        tools: [any AITool]? = nil,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async -> Result<TextGenerationResponse, AIError> {
        do {
            let response = try await retryManager.retry {
                try await self.generateText(
                    messages,
                    tools: tools,
                    maxTokens: maxTokens,
                    temperature: temperature
                )
            }
            return .success(response)
        } catch {
            if let aiError = error as? AIError {
                return .failure(aiError)
            } else {
                return .failure(.apiCallFailed(underlying: error, isRetryable: false))
            }
        }
    }
}
```

## Middleware System

```swift
// Middleware protocol for composable functionality
public protocol AIMiddleware: Sendable {
    func process<T>(
        request: T,
        next: @escaping (T) async throws -> any Sendable
    ) async throws -> any Sendable
}

// Specific middleware protocols for different operation types
public protocol TextGenerationMiddleware: AIMiddleware {
    func processTextGeneration(
        request: TextGenerationRequest,
        next: @escaping (TextGenerationRequest) async throws -> TextGenerationResponse
    ) async throws -> TextGenerationResponse
}

public protocol ObjectGenerationMiddleware: AIMiddleware {
    func processObjectGeneration<T: Codable>(
        request: ObjectGenerationRequest<T>,
        next: @escaping (ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T>
    ) async throws -> ObjectGenerationResponse<T>
}

// Default implementations for type-safe middleware
extension TextGenerationMiddleware {
    public func process<T>(
        request: T,
        next: @escaping (T) async throws -> any Sendable
    ) async throws -> any Sendable {
        guard let textRequest = request as? TextGenerationRequest else {
            return try await next(request)
        }
        
        let typedNext: (TextGenerationRequest) async throws -> TextGenerationResponse = { req in
            let result = try await next(req as! T)
            return result as! TextGenerationResponse
        }
        
        return try await processTextGeneration(request: textRequest, next: typedNext)
    }
}

extension ObjectGenerationMiddleware {
    public func process<T>(
        request: T,
        next: @escaping (T) async throws -> any Sendable
    ) async throws -> any Sendable {
        guard let objectRequest = request as? ObjectGenerationRequest<Any> else {
            return try await next(request)
        }
        
        // Complex type handling would be implemented here
        return try await next(request)
    }
}

// Built-in middleware implementations
public struct LoggingMiddleware: TextGenerationMiddleware, ObjectGenerationMiddleware {
    private let logger: Logger
    
    public init(logger: Logger = Logger(subsystem: "ai-swift", category: "middleware")) {
        self.logger = logger
    }
    
    public func processTextGeneration(
        request: TextGenerationRequest,
        next: @escaping (TextGenerationRequest) async throws -> TextGenerationResponse
    ) async throws -> TextGenerationResponse {
        logger.info("Starting text generation with \(request.messages.count) messages")
        let startTime = Date()
        
        do {
            let response = try await next(request)
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Text generation completed in \(duration)s, tokens: \(response.usage.totalTokens)")
            return response
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Text generation failed after \(duration)s: \(error)")
            throw error
        }
    }
    
    public func processObjectGeneration<T: Codable>(
        request: ObjectGenerationRequest<T>,
        next: @escaping (ObjectGenerationRequest<T>) async throws -> ObjectGenerationResponse<T>
    ) async throws -> ObjectGenerationResponse<T> {
        logger.info("Starting object generation for type \(T.self)")
        let startTime = Date()
        
        do {
            let response = try await next(request)
            let duration = Date().timeIntervalSince(startTime)
            logger.info("Object generation completed in \(duration)s, tokens: \(response.usage.totalTokens)")
            return response
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            logger.error("Object generation failed after \(duration)s: \(error)")
            throw error
        }
    }
}

public struct CachingMiddleware: TextGenerationMiddleware {
    private let cache: AICache
    
    public init(cache: AICache) {
        self.cache = cache
    }
    
    public func processTextGeneration(
        request: TextGenerationRequest,
        next: @escaping (TextGenerationRequest) async throws -> TextGenerationResponse
    ) async throws -> TextGenerationResponse {
        let cacheKey = generateCacheKey(for: request)
        
        // Try to get from cache first
        if let cachedResponse = await cache.get(key: cacheKey, type: TextGenerationResponse.self) {
            return cachedResponse
        }
        
        // Execute request and cache result
        let response = try await next(request)
        await cache.set(key: cacheKey, value: response, ttl: 3600) // 1 hour TTL
        
        return response
    }
    
    private func generateCacheKey(for request: TextGenerationRequest) -> String {
        // Generate deterministic cache key based on request
        let data = try! JSONEncoder().encode(request)
        return data.sha256
    }
}

public struct RateLimitingMiddleware: AIMiddleware {
    private let rateLimiter: RateLimiter
    
    public init(rateLimiter: RateLimiter) {
        self.rateLimiter = rateLimiter
    }
    
    public func process<T>(
        request: T,
        next: @escaping (T) async throws -> any Sendable
    ) async throws -> any Sendable {
        try await rateLimiter.acquire()
        return try await next(request)
    }
}

// Cache protocol and implementations
public protocol AICache: Sendable {
    func get<T: Codable>(key: String, type: T.Type) async -> T?
    func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async
    func remove(key: String) async
    func clear() async
}

public actor MemoryCache: AICache {
    private struct CacheEntry {
        let value: Data
        let expiry: Date
    }
    
    private var storage: [String: CacheEntry] = [:]
    
    public init() {}
    
    public func get<T: Codable>(key: String, type: T.Type) async -> T? {
        cleanExpiredEntries()
        
        guard let entry = storage[key],
              entry.expiry > Date() else {
            return nil
        }
        
        return try? JSONDecoder().decode(type, from: entry.value)
    }
    
    public func set<T: Codable>(key: String, value: T, ttl: TimeInterval) async {
        guard let data = try? JSONEncoder().encode(value) else { return }
        
        let expiry = Date().addingTimeInterval(ttl)
        storage[key] = CacheEntry(value: data, expiry: expiry)
    }
    
    public func remove(key: String) async {
        storage.removeValue(forKey: key)
    }
    
    public func clear() async {
        storage.removeAll()
    }
    
    private func cleanExpiredEntries() {
        let now = Date()
        storage = storage.filter { $0.value.expiry > now }
    }
}

// Rate limiter
public actor RateLimiter {
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    private var requestTimes: [Date] = []
    
    public init(maxRequests: Int, per timeWindow: TimeInterval) {
        self.maxRequests = maxRequests
        self.timeWindow = timeWindow
    }
    
    public func acquire() async throws {
        let now = Date()
        let cutoff = now.addingTimeInterval(-timeWindow)
        
        // Remove old requests
        requestTimes = requestTimes.filter { $0 > cutoff }
        
        // Check if we can make a request
        if requestTimes.count >= maxRequests {
            // Calculate how long to wait
            let oldestRequest = requestTimes.first!
            let waitTime = timeWindow - now.timeIntervalSince(oldestRequest)
            
            if waitTime > 0 {
                throw AIError.rateLimitExceeded(retryAfter: waitTime)
            }
        }
        
        // Record this request
        requestTimes.append(now)
    }
}

// Additional provider examples
public struct AnthropicProvider: AIProvider {
    public let name = "Anthropic"
    public let supportedModels: Set<String> = [
        "claude-3-5-sonnet-20241022", "claude-3-sonnet-20240229", "claude-3-haiku-20240307"
    ]
    
    private let apiKey: String
    private let middleware: [any AIMiddleware]
    
    public init(apiKey: String, middleware: [any AIMiddleware] = []) {
        self.apiKey = apiKey
        self.middleware = middleware
    }
    
    public func model(_ modelId: String, configuration: ModelConfiguration = ModelConfiguration()) throws -> LanguageModel {
        guard supportedModels.contains(modelId) else {
            throw AIError.modelNotFound(modelId)
        }
        
        try validateConfiguration(configuration)
        
        let rawModel = AnthropicLanguageModel(
            id: modelId,
            apiKey: apiKey,
            configuration: configuration
        )
        
        return middleware.isEmpty ? rawModel : MiddlewareWrappedModel(
            underlyingModel: rawModel,
            middleware: middleware
        )
    }
    
    public func validateConfiguration(_ configuration: ModelConfiguration) throws {
        // Anthropic-specific validation
        if let temperature = configuration.temperature {
            guard temperature >= 0.0 && temperature <= 1.0 else {
                throw AIError.invalidConfiguration("Temperature must be between 0.0 and 1.0 for Anthropic models")
            }
        }
    }
}
```

## JSON Streaming Completion Algorithm

```swift
// JSON parsing states for streaming completion
public enum JSONParsingState: Int, CaseIterable {
    case root = 0
    case array = 1
    case arrayValue = 2
    case object = 3
    case objectKey = 4
    case objectKeyEnd = 5
    case objectValue = 6
    case string = 7
    case stringEscape = 8
    case number = 9
    case literal = 10
    case error = 11
    case arrayComma = 12
    case objectComma = 13
    case objectValueEnd = 14
    case numberDecimal = 15
}

// Stack entry for tracking nested structures
public struct JSONStackEntry {
    let state: JSONParsingState
    let key: String?
    
    init(state: JSONParsingState, key: String? = nil) {
        self.state = state
        self.key = key
    }
}

// JSON streaming parser for auto-completion
public class JSONStreamingParser {
    private var stack: [JSONStackEntry] = []
    private var currentState: JSONParsingState = .root
    private var buffer: String = ""
    private var inString = false
    private var escapeNext = false
    
    public init() {}
    
    // Process a chunk of JSON and return completed/fixed JSON
    public func processChunk(_ chunk: String) -> String {
        var result = chunk
        
        for char in chunk {
            processCharacter(char)
        }
        
        // Auto-complete if we have incomplete structures
        let completions = generateCompletions()
        if !completions.isEmpty {
            result += completions
        }
        
        return result
    }
    
    private func processCharacter(_ char: Character) {
        switch char {
        case '"' where !escapeNext:
            if inString {
                // End of string
                inString = false
                transitionFromString()
            } else {
                // Start of string
                inString = true
                currentState = .string
            }
            
        case '\\' where inString:
            escapeNext = !escapeNext
            return
            
        case '{' where !inString:
            stack.append(JSONStackEntry(state: currentState))
            currentState = .object
            
        case '[' where !inString:
            stack.append(JSONStackEntry(state: currentState))
            currentState = .array
            
        case '}' where !inString:
            if currentState == .object || currentState == .objectValue || currentState == .objectValueEnd {
                popStack()
            } else {
                currentState = .error
            }
            
        case ']' where !inString:
            if currentState == .array || currentState == .arrayValue {
                popStack()
            } else {
                currentState = .error
            }
            
        case ',' where !inString:
            if currentState == .objectValue || currentState == .objectValueEnd {
                currentState = .objectComma
            } else if currentState == .arrayValue {
                currentState = .arrayComma
            }
            
        case ':' where !inString:
            if currentState == .objectKey {
                currentState = .objectKeyEnd
            }
            
        default:
            break
        }
        
        escapeNext = false
    }
    
    private func transitionFromString() {
        switch currentState {
        case .string:
            if let parent = stack.last {
                switch parent.state {
                case .object:
                    currentState = .objectKey
                case .objectKeyEnd:
                    currentState = .objectValue
                case .array:
                    currentState = .arrayValue
                default:
                    currentState = parent.state
                }
            } else {
                currentState = .root
            }
        default:
            break
        }
    }
    
    private func popStack() {
        guard !stack.isEmpty else {
            currentState = .root
            return
        }
        
        let parent = stack.removeLast()
        currentState = parent.state
        
        // Transition to appropriate state after closing
        if currentState == .object {
            currentState = .objectValueEnd
        } else if currentState == .array {
            currentState = .arrayValue
        }
    }
    
    private func generateCompletions() -> String {
        var completions = ""
        
        // Close any open string
        if inString {
            completions += "\""
        }
        
        // Close all open structures in reverse order
        for entry in stack.reversed() {
            switch entry.state {
            case .object:
                completions += "}"
            case .array:
                completions += "]"
            default:
                break
            }
        }
        
        return completions
    }
    
    // Validate if current JSON is complete and valid
    public func isComplete() -> Bool {
        return stack.isEmpty && currentState == .root && !inString
    }
    
    // Reset parser state
    public func reset() {
        stack.removeAll()
        currentState = .root
        buffer = ""
        inString = false
        escapeNext = false
    }
}

// Internal implementation notes for JSON completion:
// The JSON streaming parser is used internally within LanguageModel implementations
// to automatically complete partial JSON during object streaming. This ensures that
// users always receive valid, parseable JSON chunks without needing to manage
// completion themselves.
```

## Usage Examples

```swift
import Foundation
import os.log

// MARK: - Basic Usage Examples

// Example 1: Simple text generation
func basicTextGeneration() async throws {
    let provider = OpenAIProvider(apiKey: "your-api-key")
    
    let model = try provider.model(
        "gpt-4",
        configuration: ModelConfiguration()
            .temperature(0.7)
            .maxTokens(1000)
    )
    
    let response = try await model.generateText("Explain quantum computing in simple terms")
    print("Response: \(response.text)")
    print("Tokens used: \(response.usage.totalTokens)")
}

// Example 2: Multi-modal conversation with images
func multiModalConversation() async throws {
    let provider = OpenAIProvider(apiKey: "your-api-key")
    let model = try provider.model("gpt-4-vision-preview")
    
    let imageData = try Data(contentsOf: URL(string: "file://path/to/image.jpg")!)
    let image = MessageImage(data: imageData, mimeType: "image/jpeg")
    
    let response = try await model.generateText {
        Message.system("You are a helpful assistant that can analyze images.")
        Message.user(text: "What do you see in this image?", images: [image])
    }
    
    print("Image analysis: \(response.text)")
}

// Example 3: Structured object generation with validation
struct WeatherReport: Codable {
    let location: String
    let temperature: Double
    let condition: String
    let humidity: Int
    let windSpeed: Double
}

func structuredObjectGeneration() async throws {
    let provider = AnthropicProvider(apiKey: "your-api-key")
    let model = try provider.model("claude-3-sonnet-20240229")
    
    let validator: (WeatherReport) throws -> Void = { report in
        guard report.temperature >= -100 && report.temperature <= 100 else {
            throw ValidationError.invalidValue("temperature", report.temperature)
        }
        guard report.humidity >= 0 && report.humidity <= 100 else {
            throw ValidationError.invalidValue("humidity", report.humidity)
        }
    }
    
    let response = try await model.generateObject(
        "Generate a weather report for San Francisco today",
        as: WeatherReport.self,
        validator: validator
    )
    
    print("Weather: \(response.object)")
}

// Example 4: Streaming text with real-time processing
func streamingTextGeneration() async throws {
    let provider = OpenAIProvider(apiKey: "your-api-key")
    let model = try provider.model("gpt-4")
    
    let stream = model.streamText("Write a short story about a robot learning to paint")
    
    print("Story generation:")
    for try await chunk in stream {
        print(chunk.delta, terminator: "")
        fflush(stdout)
        
        if let finishReason = chunk.finishReason {
            print("\n\nFinished: \(finishReason)")
            if let usage = chunk.usage {
                print("Tokens: \(usage.totalTokens)")
            }
        }
    }
}

// Example 5: Streaming objects with JSON completion
struct Recipe: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
    let cookingTime: Int
}

func streamingObjectGeneration() async throws {
    let provider = OpenAIProvider(apiKey: "your-api-key")
    let model = try provider.model("gpt-4")
    
    let stream = model.streamObject(
        "Generate a recipe for chocolate chip cookies",
        as: Recipe.self
    )
    
    for try await chunk in stream {
        if let partial = chunk.partialObject {
            print("Partial recipe: \(partial)")
        }
        
        if let final = chunk.finishedObject {
            print("Final recipe: \(final)")
        }
    }
}

// MARK: - Advanced Tool Usage Examples

// Example 6: Custom tool implementation
struct CalculatorTool: AITool {
    typealias Parameters = CalculatorParameters
    typealias Result = CalculatorResult
    
    let name = "calculator"
    let description = "Perform basic mathematical operations"
    let parameters = JSONSchema.object(
        properties: [
            "operation": .string(description: "The operation to perform (add, subtract, multiply, divide)", enum: ["add", "subtract", "multiply", "divide"]),
            "a": .integer(description: "First number"),
            "b": .integer(description: "Second number")
        ],
        required: ["operation", "a", "b"]
    )
    
    func execute(_ parameters: CalculatorParameters) async throws -> CalculatorResult {
        let result: Double
        
        switch parameters.operation {
        case "add":
            result = Double(parameters.a + parameters.b)
        case "subtract":
            result = Double(parameters.a - parameters.b)
        case "multiply":
            result = Double(parameters.a * parameters.b)
        case "divide":
            guard parameters.b != 0 else {
                throw ToolExecutionError.divisionByZero
            }
            result = Double(parameters.a) / Double(parameters.b)
        default:
            throw ToolExecutionError.unsupportedOperation(parameters.operation)
        }
        
        return CalculatorResult(result: result, operation: parameters.operation)
    }
}

struct CalculatorParameters: Codable {
    let operation: String
    let a: Int
    let b: Int
}

struct CalculatorResult: Codable {
    let result: Double
    let operation: String
}

enum ToolExecutionError: Error {
    case divisionByZero
    case unsupportedOperation(String)
}

func toolUsageExample() async throws {
    let provider = OpenAIProvider(apiKey: "your-api-key")
    let model = try provider.model("gpt-4")
    
    let calculator = CalculatorTool()
    
    let response = try await model.generateText(
        [Message.user("What's 15 multiplied by 23?")],
        tools: [calculator],
        toolChoice: .auto
    )
    
    if let toolCalls = response.toolCalls {
        for toolCall in toolCalls {
            if toolCall.name == "calculator" {
                let params = try JSONDecoder().decode(
                    CalculatorParameters.self,
                    from: JSONSerialization.data(withJSONObject: toolCall.arguments)
                )
                let result = try await calculator.execute(params)
                print("Calculation result: \(result.result)")
            }
        }
    }
    
    print("AI Response: \(response.text)")
}

// MARK: - Middleware Usage Examples

// Example 7: Provider with comprehensive middleware
func middlewareExample() async throws {
    let cache = MemoryCache()
    let rateLimiter = RateLimiter(maxRequests: 10, per: 60) // 10 requests per minute
    
    let provider = OpenAIProvider(
        apiKey: "your-api-key",
        middleware: [
            LoggingMiddleware(),
            CachingMiddleware(cache: cache),
            RateLimitingMiddleware(rateLimiter: rateLimiter)
        ]
    )
    
    let model = try provider.model("gpt-4")
    
    // This request will be logged, rate-limited, and cached
    let response = try await model.generateText("Explain the theory of relativity")
    print("Response: \(response.text)")
    
    // This second identical request should come from cache
    let cachedResponse = try await model.generateText("Explain the theory of relativity")
    print("Cached response: \(cachedResponse.text)")
}

// Example 8: Error handling with Result types
func errorHandlingExample() async {
    let provider = OpenAIProvider(apiKey: "invalid-key")
    let model = try! provider.model("gpt-4")
    
    do {
        let response = try await RetryManager().retry {
            try await model.generateText("Hello, world!")
        }
        print("Success: \(response.text)")
    } catch {
        print("Failed after retries: \(error.localizedDescription)")
        
        if let aiError = error as? AIError {
            switch aiError {
            case .authenticationFailed(let message):
                print("Auth error: \(message)")
            case .rateLimitExceeded(let retryAfter):
                print("Rate limited, retry after: \(retryAfter ?? 0) seconds")
            case .networkError(let urlError):
                print("Network error: \(urlError)")
            default:
                print("Other error: \(aiError)")
            }
        }
    }
}

// MARK: - Provider Examples

// Example 9: Multiple providers and models
class AIService {
    private let openAIModel: LanguageModel
    private let anthropicModel: LanguageModel
    private let groqModel: LanguageModel
    
    init() throws {
        let openAIProvider = OpenAIProvider(apiKey: "openai-key")
        self.openAIModel = try openAIProvider.model(
            "gpt-4",
            configuration: ModelConfiguration().temperature(0.7)
        )
        
        let anthropicProvider = AnthropicProvider(apiKey: "anthropic-key")
        self.anthropicModel = try anthropicProvider.model(
            "claude-3-sonnet-20240229",
            configuration: ModelConfiguration().temperature(0.5)
        )
        
        let groqProvider = GroqProvider(apiKey: "groq-key")
        self.groqModel = try groqProvider.model(
            "llama-3.1-70b-versatile",
            configuration: ModelConfiguration().temperature(0.9)
        )
    }
    
    func generateWithFallback(_ prompt: String) async throws -> String {
        // Try OpenAI first
        do {
            let response = try await openAIModel.generateText(prompt)
            return response.text
        } catch {
            print("OpenAI failed, trying Anthropic: \(error)")
        }
        
        // Fallback to Anthropic
        do {
            let response = try await anthropicModel.generateText(prompt)
            return response.text
        } catch {
            print("Anthropic failed, trying Groq: \(error)")
        }
        
        // Final fallback to Groq
        let response = try await groqModel.generateText(prompt)
        return response.text
    }
}

// Example 10: SwiftUI Integration
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var currentResponse: String = ""
    @Published var isGenerating: Bool = false
    
    private let model: LanguageModel
    
    init() {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        self.model = try! provider.model("gpt-4")
    }
    
    func sendMessage(_ text: String) async {
        let userMessage = Message.user(text)
        messages.append(userMessage)
        
        isGenerating = true
        currentResponse = ""
        
        do {
            let stream = model.streamText(messages + [userMessage])
            
            for try await chunk in stream {
                currentResponse += chunk.delta
                
                if let finishReason = chunk.finishReason {
                    let assistantMessage = Message.assistant(currentResponse)
                    messages.append(assistantMessage)
                    currentResponse = ""
                    isGenerating = false
                }
            }
        } catch {
            print("Error: \(error)")
            isGenerating = false
        }
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                        MessageBubble(message: message)
                    }
                    
                    if viewModel.isGenerating && !viewModel.currentResponse.isEmpty {
                        MessageBubble(text: viewModel.currentResponse, isAssistant: true, isTyping: true)
                    }
                }
            }
            
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button("Send") {
                    let text = inputText
                    inputText = ""
                    
                    Task {
                        await viewModel.sendMessage(text)
                    }
                }
                .disabled(inputText.isEmpty || viewModel.isGenerating)
            }
            .padding()
        }
    }
}

struct MessageBubble: View {
    let text: String
    let isAssistant: Bool
    let isTyping: Bool
    
    init(message: Message) {
        self.text = message.content.compactMap { $0.text }.joined()
        self.isAssistant = message.role == .assistant
        self.isTyping = false
    }
    
    init(text: String, isAssistant: Bool, isTyping: Bool = false) {
        self.text = text
        self.isAssistant = isAssistant
        self.isTyping = isTyping
    }
    
    var body: some View {
        HStack {
            if !isAssistant { Spacer() }
            
            Text(text + (isTyping ? "▊" : ""))
                .padding()
                .background(isAssistant ? Color.gray.opacity(0.2) : Color.blue)
                .foregroundColor(isAssistant ? .primary : .white)
                .cornerRadius(12)
                .animation(.easeInOut(duration: 0.5), value: isTyping)
            
            if isAssistant { Spacer() }
        }
        .padding(.horizontal)
    }
}
```

This comprehensive set of examples demonstrates:

1. **Basic Operations** - Simple text and object generation
2. **Multi-modal Support** - Working with images and files
3. **Streaming Capabilities** - Real-time text and object streaming
4. **Tool Integration** - Custom tool creation and execution
5. **Middleware Usage** - Logging, caching, and rate limiting
6. **Error Handling** - Robust error management with Result types
7. **Provider Flexibility** - Multiple providers with fallback strategies
8. **SwiftUI Integration** - Real-world chat interface implementation

The examples showcase how the API feels natural to both Vercel AI SDK users (familiar patterns) and iOS developers (Swift conventions and SwiftUI integration).

## Design Rationale and Swift-Specific Choices

### 1. Protocol-Oriented Programming over Inheritance

**Choice**: Heavy use of protocols (`LanguageModel`, `AIProvider`, `AITool`, `AIMiddleware`) instead of inheritance hierarchies.

**Rationale**: 
- **Flexibility**: Allows types to conform to multiple protocols and be composed as needed
- **Testability**: Easy to create mock implementations for testing
- **Swift Convention**: Aligns with Swift's philosophy of "protocol-oriented programming"
- **Performance**: Protocol dispatch can be optimized by the compiler

**Vercel Comparison**: While Vercel uses classes and interfaces, Swift protocols provide superior composition and testing capabilities.

### 2. Result Builders for DSL-like Syntax

**Choice**: `@resultBuilder` for `ConversationBuilder` and `ValidationBuilder`.

**Rationale**:
- **SwiftUI Familiarity**: iOS developers instantly recognize this pattern
- **Type Safety**: Compile-time validation of conversation structure
- **Readability**: Clean, declarative syntax for complex operations
- **Swift Native**: Leverages Swift's unique language features

**Example**:
```swift
// SwiftUI-like conversation building
let response = try await client.generateText {
    Message.system("You are a helpful assistant")
    Message.user("Explain quantum computing")
}
```

### 3. AsyncSequence for Streaming

**Choice**: `AsyncThrowingStream` instead of callbacks or delegates.

**Rationale**:
- **Structured Concurrency**: Integrates seamlessly with Swift's async/await
- **Composability**: Easy to transform, filter, and combine streams
- **Backpressure**: Built-in support for flow control
- **Cancellation**: Automatic support for Task cancellation

**Vercel Comparison**: More elegant than JavaScript's ReadableStream, with better error handling and cancellation.

### 4. Actors for Thread Safety

**Choice**: `actor` types for `RetryManager`, `MemoryCache`, and `RateLimiter`.

**Rationale**:
- **Data Race Safety**: Compile-time guarantees against data races
- **Performance**: Efficient isolation without excessive locking
- **Swift Concurrency**: Native integration with async/await
- **Simplicity**: Clear ownership model for mutable state

### 5. Sendable Conformance

**Choice**: All public types conform to `Sendable` protocol.

**Rationale**:
- **Concurrency Safety**: Enables safe sharing across actor boundaries
- **Compiler Verification**: Static analysis prevents race conditions  
- **Future Proofing**: Prepares for strict concurrency checking
- **API Clarity**: Makes thread safety guarantees explicit

### 6. Generic Types with Associated Types

**Choice**: Generic `ObjectSchema<T>`, `ObjectChunk<T>`, and associated types in protocols.

**Rationale**:
- **Type Safety**: Compile-time validation of object types
- **Performance**: Avoids type erasure and runtime casting
- **Developer Experience**: Excellent autocomplete and error messages
- **Swift Strength**: Leverages Swift's powerful type system

### 7. Property Wrappers for Validation

**Choice**: `@Validated` property wrapper for type-level validation.

**Rationale**:
- **Declarative**: Clear, self-documenting validation rules
- **Reusable**: Can be applied to any property type
- **Swift Convention**: Familiar pattern from `@Published`, `@State`, etc.
- **Compile-time Safety**: Validation happens at property level

### 8. Provider-Centric Architecture

**Choice**: `AIProvider` as the main entry point instead of separate client abstraction.

**Rationale**:
- **Semantic Clarity**: You naturally ask providers for models, not clients
- **Reduced Complexity**: One less abstraction layer to understand
- **Clear Responsibility**: Provider manages authentication, middleware, and model creation
- **No API Confusion**: Single entry point prevents middleware bypass issues

### 9. Structured Error Handling

**Choice**: Comprehensive `AIError` enum with `LocalizedError` conformance.

**Rationale**:
- **Swift Convention**: Enums are the idiomatic error type in Swift
- **Pattern Matching**: Enables exhaustive error handling
- **Localization**: Built-in support for user-facing error messages
- **Contextual Information**: Associated values provide error details

### 10. Middleware Composition

**Choice**: Function composition for middleware chain execution.

**Rationale**:
- **Functional Programming**: Aligns with Swift's functional capabilities
- **Composability**: Easy to combine and reorder middleware
- **Type Safety**: Middleware type constraints prevent misuse
- **Performance**: No overhead compared to class-based approaches

### 11. Extension-Based API Organization

**Choice**: Core functionality added via extensions rather than massive classes.

**Rationale**:
- **Modularity**: Related functionality grouped logically
- **Readability**: Easier to understand and maintain
- **Testability**: Can test extensions in isolation
- **Swift Convention**: Preferred way to extend types

### 12. Value Types Over Reference Types

**Choice**: `struct` types for data models, configurations, and requests.

**Rationale**:
- **Performance**: Stack allocation and value semantics
- **Thread Safety**: Immutable by default, safe to share
- **Predictability**: No shared mutable state surprises
- **Swift Preference**: Structs are preferred unless reference semantics needed

### 13. Native JSON Parsing Integration

**Choice**: Built-in `Codable` support with custom JSON streaming parser.

**Rationale**:
- **Performance**: Avoids multiple JSON parsing passes
- **Type Safety**: Automatic conversion to Swift types
- **Streaming**: Maintains valid JSON during incremental parsing
- **Swift Integration**: Seamless with existing `Codable` infrastructure

### 14. SwiftUI-First Design

**Choice**: API designed with SwiftUI integration as a primary consideration.

**Rationale**:
- **Modern iOS Development**: SwiftUI is the future of iOS development
- **Reactive Patterns**: `@Published` properties work naturally with the API
- **Declarative UI**: Streaming responses integrate well with UI updates
- **Developer Productivity**: Reduces boilerplate for common UI patterns

### 15. Provider Abstraction Strategy

**Choice**: Protocol-based provider system with minimal common interface.

**Rationale**:
- **Flexibility**: Easy to add new providers without breaking changes
- **Testing**: Simple to mock different providers
- **Future-Proofing**: Can accommodate new AI capabilities
- **Performance**: No unnecessary abstraction overhead

## Key Advantages Over Direct Vercel AI SDK Port

1. **Compile-Time Safety**: Swift's type system catches many errors at compile time that would be runtime errors in TypeScript
2. **Memory Safety**: No undefined behavior or memory leaks with Swift's automatic reference counting
3. **Structured Concurrency**: More robust async patterns than JavaScript Promises
4. **Native Integration**: Seamless integration with iOS/macOS development patterns
5. **Performance**: Native compilation and value types provide better performance
6. **Developer Experience**: Superior autocomplete, error messages, and debugging

## Maintaining Vercel AI SDK Familiarity

While embracing Swift conventions, the design maintains conceptual compatibility:

- **Same method names**: `generateText`, `generateObject`, `streamText`, `streamObject`
- **Similar parameters**: Temperature, maxTokens, tools, etc.
- **Compatible concepts**: Messages, tools, streaming, providers
- **Equivalent functionality**: All major Vercel AI SDK features represented

This approach ensures Vercel AI SDK users can quickly adopt the Swift version while iOS developers feel completely at home with the API design.

## Architecture Summary

The final architecture provides a clean, intuitive API:

```swift
// Setup provider with middleware
let provider = OpenAIProvider(
    apiKey: "your-api-key",
    middleware: [LoggingMiddleware(), CachingMiddleware()]
)

// Create configured models
let creativeModel = try provider.model("gpt-4", configuration: 
    ModelConfiguration().temperature(0.9)
)

// Use naturally with full convenience methods
let response = try await creativeModel.generateText("Write a haiku about Swift")

// Streaming with automatic JSON completion
for try await chunk in creativeModel.streamObject("Generate a recipe", as: Recipe.self) {
    // Process streaming object chunks
}
```

**Key Benefits:**
- ✅ **Single Entry Point**: LanguageModel methods are the only way to call AI operations
- ✅ **Middleware Always Applied**: Impossible to bypass because raw models are internal
- ✅ **Ergonomic API**: Call methods directly on configured models
- ✅ **Per-Operation Configuration**: Model and config specified where it matters
- ✅ **JSON Completion Hidden**: Automatically applied during object streaming
- ✅ **Rich Enum Support**: JSONSchema supports string, integer, number, and boolean enums
- ✅ **Type-Safe Validation**: Property wrappers and builder patterns for validation
- ✅ **SwiftUI Integration**: Designed for modern iOS development patterns