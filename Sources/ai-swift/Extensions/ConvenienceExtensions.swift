import Foundation

// MARK: - Language Model Convenience Extensions

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public extension LanguageModel {
    
    // MARK: - Text Generation Convenience
    
    /// Generate text from a simple string prompt
    func generateText(_ prompt: String) async throws -> TextGenerationResponse {
        let request = TextGenerationRequest(messages: [.user(prompt)])
        return try await generateText(request)
    }
    
    /// Generate text with system message
    func generateText(_ prompt: String, system: String) async throws -> TextGenerationResponse {
        let request = TextGenerationRequest(
            messages: [.user(prompt)],
            system: system
        )
        return try await generateText(request)
    }
    
    /// Generate text with tools
    func generateText(_ prompt: String, tools: [AITool]) async throws -> TextGenerationResponse {
        let request = TextGenerationRequest(
            messages: [.user(prompt)],
            tools: tools
        )
        return try await generateText(request)
    }
    
    /// Stream text from a simple string prompt
    func streamText(_ prompt: String) -> AsyncThrowingStream<TextChunk, Error> {
        let request = TextGenerationRequest(messages: [.user(prompt)])
        return streamText(request)
    }
    
    /// Stream text with system message
    func streamText(_ prompt: String, system: String) -> AsyncThrowingStream<TextChunk, Error> {
        let request = TextGenerationRequest(
            messages: [.user(prompt)],
            system: system
        )
        return streamText(request)
    }
    
    // MARK: - Object Generation Convenience
    
    /// Generate object from prompt and schema
    func generateObject<T: Codable>(
        _ prompt: String,
        schema: JSONSchema,
        type: T.Type
    ) async throws -> ObjectGenerationResponse<T> {
        let request = ObjectGenerationRequest<T>(
            messages: [.user(prompt)],
            schema: schema
        )
        return try await generateObject(request)
    }
    
    /// Generate object with system message
    func generateObject<T: Codable>(
        _ prompt: String,
        system: String,
        schema: JSONSchema,
        type: T.Type
    ) async throws -> ObjectGenerationResponse<T> {
        let request = ObjectGenerationRequest<T>(
            messages: [.user(prompt)],
            schema: schema,
            system: system
        )
        return try await generateObject(request)
    }
    
    /// Stream object from prompt and schema
    func streamObject<T: Codable>(
        _ prompt: String,
        schema: JSONSchema,
        type: T.Type
    ) -> AsyncThrowingStream<ObjectChunk<T>, Error> {
        let request = ObjectGenerationRequest<T>(
            messages: [.user(prompt)],
            schema: schema
        )
        return streamObject(request)
    }
    
    // MARK: - Embedding Convenience
    
    /// Generate embedding from text
    func embed(_ text: String) async throws -> EmbeddingResponse {
        let request = EmbeddingRequest(value: .text(text))
        return try await embed(request)
    }
    
    /// Generate embeddings from multiple texts
    func embedMany(_ texts: [String]) async throws -> BatchEmbeddingResponse {
        let request = BatchEmbeddingRequest(values: texts.map { .text($0) })
        return try await embedMany(request)
    }
}

// MARK: - Request Builder Extensions

public extension TextGenerationRequest {
    /// Create request from conversation messages
    static func conversation(_ messages: [CoreMessage]) -> TextGenerationRequest {
        TextGenerationRequest(messages: messages)
    }
    
    /// Create request with system prompt and user message
    static func chat(user: String, system: String? = nil) -> TextGenerationRequest {
        var messages: [CoreMessage] = []
        if let system = system {
            messages.append(.system(system))
        }
        messages.append(.user(user))
        return TextGenerationRequest(messages: messages)
    }
    
    /// Add tools to the request
    func withTools(_ tools: [AITool]) -> TextGenerationRequest {
        TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            maxSteps: maxSteps
        )
    }
    
    /// Set tool choice strategy
    func withToolChoice(_ choice: ToolChoice) -> TextGenerationRequest {
        TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: choice,
            system: system,
            maxSteps: maxSteps
        )
    }
    
    /// Set maximum steps for multi-step execution
    func maxSteps(_ steps: Int) -> TextGenerationRequest {
        TextGenerationRequest(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            system: system,
            maxSteps: steps
        )
    }
}

public extension ObjectGenerationRequest {
    /// Create request from prompt
    static func prompt<U: Codable & Sendable>(
        _ prompt: String,
        schema: JSONSchema,
        type: U.Type
    ) -> ObjectGenerationRequest<U> {
        ObjectGenerationRequest<U>(
            messages: [.user(prompt)],
            schema: schema
        )
    }
    
    /// Add schema description
    func withDescription(_ description: String) -> ObjectGenerationRequest<T> {
        ObjectGenerationRequest<T>(
            messages: messages,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: description,
            mode: mode,
            system: system,
            tools: tools,
            toolChoice: toolChoice,
            maxSteps: maxSteps
        )
    }
    
    /// Set generation mode
    func mode(_ mode: ObjectGenerationMode) -> ObjectGenerationRequest<T> {
        ObjectGenerationRequest<T>(
            messages: messages,
            schema: schema,
            schemaName: schemaName,
            schemaDescription: schemaDescription,
            mode: mode,
            system: system,
            tools: tools,
            toolChoice: toolChoice,
            maxSteps: maxSteps
        )
    }
}

// MARK: - Stream Processing Extensions

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
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
    
    /// Filter chunks by condition
    func filter(_ predicate: @escaping @Sendable (TextChunk) -> Bool) -> AsyncThrowingStream<TextChunk, Error> {
        AsyncThrowingStream<TextChunk, Error> { continuation in
            Task {
                do {
                    for try await chunk in self {
                        if predicate(chunk) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public extension AsyncThrowingStream where Element == AnyObjectChunk {
    /// Collect final snapshot when stream completes
    func collectSnapshot() async throws -> String {
        var finalSnapshot = ""
        for try await chunk in self {
            finalSnapshot = chunk.snapshot
        }
        return finalSnapshot
    }
}

// MARK: - Tool Building Extensions

public extension AITool {
    /// Create function tool
    static func function(
        name: String,
        description: String,
        parameters: JSONSchema
    ) -> AITool {
        AITool(
            type: .function,
            function: ToolFunction(
                name: name,
                description: description,
                parameters: parameters
            )
        )
    }
}

public extension ToolFunction {
    /// Create function with string parameter
    static func stringParameter(
        name: String,
        description: String,
        parameterName: String = "input",
        parameterDescription: String = "Input parameter"
    ) -> ToolFunction {
        ToolFunction(
            name: name,
            description: description,
            parameters: .object(
                properties: [
                    parameterName: .string().withDescription(parameterDescription)
                ],
                required: [parameterName]
            )
        )
    }
    
    /// Create function with multiple parameters
    static func parameters(
        name: String,
        description: String,
        @SchemaBuilder parameters: () -> [String: JSONSchema],
        required: [String] = []
    ) -> ToolFunction {
        ToolFunction(
            name: name,
            description: description,
            parameters: .object(
                properties: parameters(),
                required: required.isEmpty ? nil : required
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
    
    /// Add title to schema
    func withTitle(_ title: String) -> JSONSchema {
        let def = self.definition
        return .definition(SchemaDefinition(
            type: def.type,
            properties: def.properties,
            items: def.items,
            required: def.required,
            enum: def.`enum`,
            const: def.const,
            title: title,
            description: def.description,
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
    
    /// Add examples to schema
    func withExamples(_ examples: [JSONSchemaValue]) -> JSONSchema {
        let def = self.definition
        return .definition(SchemaDefinition(
            type: def.type,
            properties: def.properties,
            items: def.items,
            required: def.required,
            enum: def.`enum`,
            const: def.const,
            title: def.title,
            description: def.description,
            examples: examples,
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

// MARK: - Error Handling Extensions

public extension Result where Failure: AIError {
    /// Map success value while preserving AI error type
    func mapAI<NewSuccess>(_ transform: (Success) throws -> NewSuccess) -> Result<NewSuccess, Failure> {
        switch self {
        case .success(let value):
            do {
                return .success(try transform(value))
            } catch {
                if let aiError = error as? Failure {
                    return .failure(aiError)
                } else {
                    // This shouldn't happen with proper error typing
                    fatalError("Non-AI error in AI result transformation")
                }
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Get value or throw AI error
    func getValue() throws -> Success {
        switch self {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}