import Foundation

// MARK: - Convenience Extensions

// These extensions provide simplified interfaces for common operations
// In the new architecture, most operations should be done through AIClient

// MARK: - Message Convenience Extensions

public extension Message {
    /// Create a user message with text content
    static func user(_ text: String) -> Message {
        Message(role: .user, content: [.text(text)])
    }
    
    /// Create a system message with text content
    static func system(_ text: String) -> Message {
        Message(role: .system, content: [.text(text)])
    }
    
    /// Create an assistant message with text content
    static func assistant(_ text: String) -> Message {
        Message(role: .assistant, content: [.text(text)])
    }
}


// MARK: - Configuration Chaining

public extension ModelConfiguration {
    /// Chain multiple configuration modifications
    func configure(_ modifier: (ModelConfiguration) -> ModelConfiguration) -> ModelConfiguration {
        modifier(self)
    }
    
    /// Apply configuration if condition is true
    func `if`(_ condition: Bool, _ modifier: (ModelConfiguration) -> ModelConfiguration) -> ModelConfiguration {
        condition ? modifier(self) : self
    }
}

// MARK: - Tool Building Extensions

public extension Tool {
    /// Create function tool
    static func function(
        name: String,
        description: String,
        parameters: JSONSchema
    ) -> Tool {
        Tool(
            type: .function,
            function: ToolFunction(
                name: name,
                description: description,
                parameters: parameters
            )
        )
    }
}

// MARK: - Schema Building Extensions

public extension JSONSchema {
    /// Add description to schema
    func withDescription(_ description: String) -> JSONSchema {
        let def = self.definition
        return .definition(SchemaDefinition(
            type: def.type,
            properties: def.properties,
            items: def.items,
            required: def.required,
            enum: def.`enum`,
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
        ))
    }
}

// MARK: - Stream Processing Extensions

public extension AsyncThrowingStream where Element == TextChunk {
    /// Collect all text chunks into final text
    func collectText() async throws -> String {
        var result = ""
        for try await chunk in self {
            result += chunk.delta
        }
        return result
    }
    
    /// Get only the text deltas
    func deltas() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream<String, Error> { continuation in
            Task {
                do {
                    for try await chunk in self {
                        continuation.yield(chunk.delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}