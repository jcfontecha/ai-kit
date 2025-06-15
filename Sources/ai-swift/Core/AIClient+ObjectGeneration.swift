import Foundation

// MARK: - Object Generation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension AIClient {
    
    /// Generate a structured object response from the given model, messages, and schema.
    ///
    /// This method handles structured data generation with JSON schema validation:
    /// 1. Applies request middleware
    /// 2. Validates the provided schema
    /// 3. Calls provider with schema-constrained generation
    /// 4. Validates response against schema
    /// 5. Deserializes to the specified type
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateObject<T: Codable>(_ model: LanguageModel, messages: [Message], schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode  
        let providerMode = createProviderMode(
            generationMode: effectiveMode,
            outputStrategy: .object,
            schema: schema
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Parse the JSON response into the target type (framework responsibility)
        let jsonObject = try parseJSONResponse(providerResponse.content, as: T.self)
        
        // 6. Validate the object against schema
        let validationResult = schema.validate(jsonObject)
        
        // 7. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<T>(
            object: jsonObject,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: validationResult
        )
        
        // 8. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for object generation from a simple prompt
    func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(model, messages: messages, schema: schema, mode: mode)
    }
    
    /// Generate an array of structured objects from the given model, messages, and element schema.
    ///
    /// This method specializes in generating arrays of objects with the provider's optimal approach:
    /// 1. Determines effective generation mode based on provider capabilities
    /// 2. Creates provider request with array output strategy  
    /// 3. Calls provider's raw text generation with mode information
    /// 4. Parses the JSON array response into the specified element type
    /// 5. Validates each element against the provided schema
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - elementSchema: The schema defining the structure of each array element
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<[T]>` containing the generated array and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateArray<T: Codable>(_ model: LanguageModel, messages: [Message], elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode  
        let providerMode = createProviderMode(
            generationMode: effectiveMode,
            outputStrategy: .array,
            schema: elementSchema
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Parse the JSON response into the target array type (framework responsibility)
        let jsonArray = try parseJSONResponse(providerResponse.content, as: [T].self)
        
        // 7. Validate each element against the schema
        var validationResults: [ObjectValidationResult] = []
        for element in jsonArray {
            validationResults.append(elementSchema.validate(element))
        }
        
        // 8. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<[T]>(
            object: jsonArray,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: validationResults.first // Use first validation result for compatibility
        )
        
        // 9. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for array generation from a simple prompt
    func generateArray<T: Codable>(_ model: LanguageModel, prompt: String, elementSchema: ObjectSchema<T>, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        let messages = [Message.user(prompt)]
        return try await generateArray(model, messages: messages, elementSchema: elementSchema, mode: mode)
    }
    
    /// Generate an enum value from a predefined set of options.
    ///
    /// This method handles enum generation by constraining the model to select from
    /// a specific set of predefined values:
    /// 1. Determines effective generation mode based on provider capabilities
    /// 2. Creates provider request with enum output strategy
    /// 3. Calls provider's raw text generation with mode information
    /// 4. Validates the response against the allowed values
    /// 5. Returns the selected enum value
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - values: Array of allowed enum values
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<String>` containing the selected enum value
    /// - Throws: `AIError` if the response doesn't match any allowed values
    func generateEnum(_ model: LanguageModel, messages: [Message], values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String> {
        // 1. Determine the actual mode to use
        let effectiveMode = determineEffectiveMode(requestedMode: mode, provider: model.provider)
        
        // 2. Create provider mode based on effective generation mode
        let providerMode = createProviderModeForEnum(
            generationMode: effectiveMode,
            values: values
        )
        
        // 3. Create provider request with the determined mode
        let request = ProviderRequest(
            modelId: model.modelId,
            messages: messages,
            configuration: model.configuration,
            tools: extractToolsFromMode(providerMode),
            mode: providerMode
        )
        
        // 4. Apply request middleware
        let processedRequest = try await applyRequestMiddleware(request)
        
        // 5. Call provider's raw text generation with mode information
        let providerResponse = try await model.provider.generateTextRaw(processedRequest)
        
        // 6. Extract and validate the enum value
        let selectedValue = providerResponse.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        // Remove potential JSON quotes if present
        let cleanValue = selectedValue.hasPrefix("\"") && selectedValue.hasSuffix("\"") 
            ? String(selectedValue.dropFirst().dropLast())
            : selectedValue
        
        // Validate against allowed values
        guard values.contains(cleanValue) else {
            throw AIGenerationError.schemaValidationError(
                objectData: providerResponse.content,
                validationErrors: ["Generated value '\(cleanValue)' is not in allowed values: \(values.joined(separator: ", "))"]
            )
        }
        
        // 7. Build final ObjectResponse
        let finalMessages = messages + [Message.assistant(providerResponse.content)]
        
        let objectResponse = ObjectResponse<String>(
            object: cleanValue,
            finishReason: providerResponse.finishReason,
            usage: providerResponse.usage,
            messages: finalMessages,
            steps: nil,
            responseId: nil,
            modelId: model.modelId,
            timestamp: Date(),
            warnings: nil,
            responseHeaders: nil,
            rawJSON: providerResponse.content,
            validationResult: ObjectValidationResult(isValid: true) // Enum validation passed
        )
        
        // 8. Apply response middleware and return
        return try await applyResponseMiddleware(objectResponse)
    }
    
    /// Convenience method for enum generation from a simple prompt
    func generateEnum(_ model: LanguageModel, prompt: String, values: [String], mode: GenerationMode = .auto) async throws -> ObjectResponse<String> {
        let messages = [Message.user(prompt)]
        return try await generateEnum(model, messages: messages, values: values, mode: mode)
    }
    
    /// Generate a structured object from a simple string prompt.
    ///
    /// This is a convenience method that wraps the prompt in a user message
    /// and calls the full `generateObject` method.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - schema: The schema defining the structure of the expected object
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateObject<T: Codable>(_ model: LanguageModel, prompt: String, schema: ObjectSchema<T>) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(model, messages: messages, schema: schema)
    }
}

// MARK: - Object Generation Private Helpers

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Determine the effective generation mode based on requested mode and provider capabilities
    func determineEffectiveMode(requestedMode: GenerationMode, provider: any AIProvider) -> GenerationMode {
        // If auto mode, use provider's default
        if requestedMode == .auto {
            return provider.defaultGenerationMode
        }
        
        // Check if provider supports the requested mode
        if provider.supportedGenerationModes.contains(requestedMode) {
            return requestedMode
        }
        
        // Fall back to provider's default if requested mode is not supported
        return provider.defaultGenerationMode
    }
    
    /// Create provider mode based on generation mode and output strategy
    func createProviderMode<T: Codable>(
        generationMode: GenerationMode,
        outputStrategy: OutputStrategy,
        schema: ObjectSchema<T>
    ) -> ProviderMode {
        switch generationMode {
        case .json:
            return .objectJSON(
                schema: schema.jsonSchema,
                name: schema.name,
                description: schema.description
            )
        case .tool:
            // Create a tool that represents the schema
            let tool = createToolFromSchema(schema: schema, outputStrategy: outputStrategy)
            return .objectTool(tool: tool)
        case .auto:
            // This shouldn't happen as auto should be resolved by determineEffectiveMode
            return .objectJSON(
                schema: schema.jsonSchema,
                name: schema.name,
                description: schema.description
            )
        }
    }
    
    /// Extract tools from provider mode if applicable
    func extractToolsFromMode(_ mode: ProviderMode) -> [Tool]? {
        switch mode {
        case .regular(let tools, _):
            return tools
        case .objectTool(let tool):
            return [tool]
        case .objectJSON:
            return nil
        }
    }
    
    /// Create a tool from schema for tool-based structured output
    func createToolFromSchema<T: Codable>(
        schema: ObjectSchema<T>,
        outputStrategy: OutputStrategy
    ) -> Tool {
        let functionName = schema.name ?? "generate_object"
        let description = schema.description ?? "Generate a structured object"
        
        return Tool(
            type: .function,
            function: ToolFunction(
                name: functionName,
                description: description,
                parameters: schema.jsonSchema
            )
        )
    }
    
    /// Create provider mode for enum generation
    func createProviderModeForEnum(
        generationMode: GenerationMode,
        values: [String]
    ) -> ProviderMode {
        switch generationMode {
        case .json:
            // Create a simple schema for enum values
            let enumSchema = JSONSchema.string(enum: values)
            return .objectJSON(
                schema: enumSchema,
                name: "enum_value",
                description: "Select one value from the allowed options"
            )
        case .tool:
            // Create a tool for enum selection
            let tool = createToolFromEnum(values: values)
            return .objectTool(tool: tool)
        case .auto:
            // Default to JSON mode for enums
            let enumSchema = JSONSchema.string(enum: values)
            return .objectJSON(
                schema: enumSchema,
                name: "enum_value",
                description: "Select one value from the allowed options"
            )
        }
    }
    
    /// Create a tool from enum values for tool-based enum selection
    func createToolFromEnum(values: [String]) -> Tool {
        let enumSchema = JSONSchema.string(enum: values)
        
        return Tool(
            type: .function,
            function: ToolFunction(
                name: "select_enum_value",
                description: "Select one value from the available options",
                parameters: JSONSchema.object(properties: [
                    "value": enumSchema
                ], required: ["value"])
            )
        )
    }
}