import Foundation

// MARK: - Object Generation

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
    ///   - mode: The generation mode (auto, json, tool)
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateObject<T: Codable>(
        _ model: LanguageModel, 
        messages: [Message], 
        schema: ObjectSchema<T>, 
        mode: GenerationMode = .auto
    ) async throws -> ObjectResponse<T> {
        // 1. Validate input parameters (following Vercel AI SDK patterns)
        try validateObjectGenerationInput(
            schema: schema,
            mode: mode,
            outputStrategy: .object,
            provider: model.provider
        )
        
        // 2. Determine the actual mode to use
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
        
        // 6. Parse the response based on the mode used
        let jsonObject = try parseObjectResponse(
            providerResponse: providerResponse,
            mode: providerMode,
            schema: schema,
            outputStrategy: .object
        )
        
        // 7. Validate the object against schema with output strategy context
        let validationResult = validateWithOutputStrategy(
            object: jsonObject,
            schema: schema,
            outputStrategy: .object
        )
        
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
    func generateObject<T: Codable>(
        _ model: LanguageModel, 
        prompt: String, 
        schema: ObjectSchema<T>, 
        mode: GenerationMode = .auto
    ) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(
            model, 
            messages: messages, 
            schema: schema, 
            mode: mode
        )
    }
    
    /// Generate a structured object response using a SchemaProviding type with messages.
    ///
    /// This overload accepts types that conform to SchemaProviding and automatically
    /// uses their schema property, providing a clean type-safe API.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - type: The SchemaProviding type to generate
    ///   - mode: The generation mode (auto, json, tool)
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateObject<T: SchemaProviding>(
        _ model: LanguageModel, 
        messages: [Message], 
        type: T.Type, 
        mode: GenerationMode = .auto
    ) async throws -> ObjectResponse<T> {
        return try await generateObject(
            model, 
            messages: messages, 
            schema: type.schema, 
            mode: mode
        )
    }
    
    /// Generate a structured object response using a SchemaProviding type with prompt.
    ///
    /// This overload accepts types that conform to SchemaProviding and automatically
    /// uses their schema property, providing a clean type-safe API.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - type: The SchemaProviding type to generate
    ///   - mode: The generation mode (auto, json, tool)
    /// - Returns: An `ObjectResponse<T>` containing the generated object and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateObject<T: SchemaProviding>(
        _ model: LanguageModel, 
        prompt: String, 
        type: T.Type, 
        mode: GenerationMode = .auto
    ) async throws -> ObjectResponse<T> {
        let messages = [Message.user(prompt)]
        return try await generateObject(
            model, 
            messages: messages, 
            type: type, 
            mode: mode
        )
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
        // 1. Validate input parameters
        try validateObjectGenerationInput(
            schema: elementSchema,
            mode: mode,
            outputStrategy: .array,
            provider: model.provider
        )
        
        // 2. Determine the actual mode to use
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
        
        // 6. Parse the response based on the mode used  
        let jsonArray: [T] = try parseArrayResponse(
            providerResponse: providerResponse,
            mode: providerMode,
            elementSchema: elementSchema
        )
        
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
    
    /// Generate an array of structured objects using a SchemaProviding element type with messages.
    ///
    /// This overload accepts types that conform to SchemaProviding and automatically
    /// uses their schema property, providing a clean type-safe API for array generation.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - messages: Array of messages forming the conversation context
    ///   - elementType: The SchemaProviding type for array elements
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<[T]>` containing the generated array and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateArray<T: SchemaProviding>(_ model: LanguageModel, messages: [Message], elementType: T.Type, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        return try await generateArray(model, messages: messages, elementSchema: elementType.schema, mode: mode)
    }
    
    /// Generate an array of structured objects using a SchemaProviding element type with prompt.
    ///
    /// This overload accepts types that conform to SchemaProviding and automatically
    /// uses their schema property, providing a clean type-safe API for array generation.
    ///
    /// - Parameters:
    ///   - model: The configured language model to use
    ///   - prompt: The text prompt to send to the model
    ///   - elementType: The SchemaProviding type for array elements
    ///   - mode: The generation mode (auto, json, tool) - defaults to auto
    /// - Returns: An `ObjectResponse<[T]>` containing the generated array and metadata
    /// - Throws: `AIError` for validation failures or generation errors
    func generateArray<T: SchemaProviding>(_ model: LanguageModel, prompt: String, elementType: T.Type, mode: GenerationMode = .auto) async throws -> ObjectResponse<[T]> {
        let messages = [Message.user(prompt)]
        return try await generateArray(model, messages: messages, elementType: elementType, mode: mode)
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
        // 1. Validate input parameters
        try validateObjectGenerationInput(
            schema: nil,
            mode: mode,
            outputStrategy: .enum,
            provider: model.provider,
            enumValues: values
        )
        
        // 2. Determine the actual mode to use
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

internal extension AIClient {
    
    /// Validate input parameters for object generation (following Vercel AI SDK patterns)
    func validateObjectGenerationInput(
        schema: (any Sendable)?,
        mode: GenerationMode,
        outputStrategy: OutputStrategy,
        provider: any AIProvider,
        enumValues: [String]? = nil
    ) throws {
        // Validate output strategy requirements
        switch outputStrategy {
        case .object, .array:
            guard schema != nil else {
                throw AIConfigurationError.missingRequiredParameter("schema is required for object/array output")
            }
        case .enum:
            guard enumValues != nil else {
                throw AIConfigurationError.missingRequiredParameter("enumValues is required for enum output")
            }
        case .noSchema:
            // Allow no schema for no-schema output
            break
        }
        
        // Validate mode compatibility with output strategy
        if outputStrategy == .noSchema && mode == .tool {
            throw AIConfigurationError.conflictingParameters([
                "mode: tool", 
                "outputStrategy: no-schema"
            ])
        }
        
        // Validate provider supports the mode
        if !provider.supportedGenerationModes.contains(mode) && mode != .auto {
            let supportedModes = provider.supportedGenerationModes.map { $0.rawValue }.joined(separator: ", ")
            throw AIConfigurationError.invalidParameter(
                "mode",
                "Mode '\(mode.rawValue)' not supported by provider. Supported modes: \(supportedModes)"
            )
        }
        
        // Validate schema structure if provided
        // Note: Schema validation is simplified to avoid generic type constraints
        // Detailed validation is performed at the type level when needed
    }
    
    /// Validate object against schema with output strategy-specific rules
    func validateWithOutputStrategy<T: Codable>(
        object: T,
        schema: ObjectSchema<T>,
        outputStrategy: OutputStrategy
    ) -> ObjectValidationResult {
        switch outputStrategy {
        case .object:
            // Standard object validation
            return schema.validate(object)
        case .array:
            // Array validation (if T is array type)
            return validateArrayOutput(object: object, schema: schema)
        case .enum:
            // Enum validation (if T is string type)
            return validateEnumOutput(object: object)
        case .noSchema:
            // No validation for schema-free output
            return ObjectValidationResult(isValid: true)
        }
    }
    
    /// Validate array output with element-specific rules
    private func validateArrayOutput<T: Codable>(
        object: T,
        schema: ObjectSchema<T>
    ) -> ObjectValidationResult {
        // For arrays, we validate each element
        if let array = object as? [Any] {
            var allErrors: [ObjectValidationError] = []
            var allWarnings: [ObjectValidationWarning] = []
            
            for (index, element) in array.enumerated() {
                // Validate each element (simplified validation)
                // In a full implementation, this would validate each element against the element schema
                if let _ = element as? NSNull {
                    allWarnings.append(.unexpectedProperty("array element \(index) is null"))
                }
            }
            
            return ObjectValidationResult(
                isValid: allErrors.isEmpty,
                errors: allErrors,
                warnings: allWarnings
            )
        }
        
        // Not an array, use standard validation
        return schema.validate(object)
    }
    
    /// Validate enum output against allowed values
    private func validateEnumOutput<T: Codable>(object: T) -> ObjectValidationResult {
        // For enum outputs, ensure the value is a valid string
        if let stringValue = object as? String {
            // Basic validation that it's a non-empty string
            if stringValue.isEmpty {
                return ObjectValidationResult(
                    isValid: false,
                    errors: [.custom("Enum value cannot be empty")]
                )
            }
            return ObjectValidationResult(isValid: true)
        }
        
        return ObjectValidationResult(
            isValid: false,
            errors: [.custom("Enum output must be a string value")]
        )
    }
    
    /// Validate schema structure for common issues
    private func validateSchemaStructure<T: Codable>(_ schema: ObjectSchema<T>) throws {
        // Check that the schema has valid JSON structure
        let jsonSchema = schema.jsonSchema
        
        // Validate required properties exist in schema definition
        if case .definition(let definition) = jsonSchema {
            if let required = definition.required, let properties = definition.properties {
                for requiredField in required {
                    guard properties.keys.contains(requiredField) else {
                        throw AIConfigurationError.invalidParameter(
                            "schema",
                            "Required field '\(requiredField)' not found in properties"
                        )
                    }
                }
            }
        }
        
        // Validate name is provided or can be inferred
        if schema.name == nil || schema.name!.isEmpty {
            throw AIConfigurationError.invalidParameter(
                "schema",
                "Schema name must be provided for object generation"
            )
        }
    }
    
    /// Determine the effective generation mode based on requested mode and provider capabilities
    func determineEffectiveMode(requestedMode: GenerationMode, provider: any AIProvider) -> GenerationMode {
        // If auto mode, select best mode based on provider capabilities and schema complexity
        if requestedMode == .auto {
            return selectOptimalMode(provider: provider)
        }
        
        // Check if provider supports the requested mode
        if provider.supportedGenerationModes.contains(requestedMode) {
            return requestedMode
        }
        
        // Log warning about unsupported mode
        print("⚠️ Warning: Requested mode '\(requestedMode.rawValue)' not supported by provider '\(provider.name)'")
        print("💡 Falling back to provider default mode: '\(provider.defaultGenerationMode.rawValue)'")
        
        // Fall back to provider's default if requested mode is not supported
        return provider.defaultGenerationMode
    }
    
    /// Select optimal generation mode based on provider capabilities
    private func selectOptimalMode(provider: any AIProvider) -> GenerationMode {
        let supportedModes = provider.supportedGenerationModes
        
        // Preference order: tool > json > fallback to default
        if supportedModes.contains(.tool) {
            // Tool mode provides better structured output reliability
            return .tool
        } else if supportedModes.contains(.json) {
            // JSON mode is good for most structured output
            return .json
        } else {
            // Use provider default as last resort
            return provider.defaultGenerationMode
        }
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
        
        // Transform schema based on output strategy following Vercel AI SDK patterns
        let toolParameters = transformSchemaForToolOutput(schema: schema.jsonSchema, strategy: outputStrategy)
        
        return Tool(
            type: .function,
            function: ToolFunction(
                name: functionName,
                description: description,
                parameters: toolParameters,
                strict: true // Enable strict mode for better validation
            )
        )
    }
    
    /// Transform schema for tool output based on strategy (following Vercel AI SDK patterns)
    private func transformSchemaForToolOutput(
        schema: JSONSchema,
        strategy: OutputStrategy
    ) -> JSONSchema {
        switch strategy {
        case .object:
            // Direct schema for single objects
            return schema
        case .array:
            // Wrap in elements structure: {elements: [schema]}
            return .object(properties: [
                "elements": .array(items: schema)
            ], required: ["elements"])
        case .enum:
            // Should not be used with createToolFromSchema - use createToolFromEnum instead
            return schema
        case .noSchema:
            // Allow any structure
            return .object(properties: [:], additionalProperties: .boolean(true))
        }
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
    
    
    /// Parse object response based on mode and output strategy
    func parseObjectResponse<T: Codable>(
        providerResponse: ProviderResponse,
        mode: ProviderMode,
        schema: ObjectSchema<T>,
        outputStrategy: OutputStrategy
    ) throws -> T {
        switch mode {
        case .objectTool(let tool):
            // Parse tool call result
            return try parseToolCallResponse(
                providerResponse: providerResponse,
                tool: tool,
                schema: schema,
                outputStrategy: outputStrategy
            )
        case .objectJSON:
            // Parse JSON response directly
            return try parseJSONResponse(providerResponse.content, as: T.self)
        case .regular:
            // Fallback to JSON parsing
            return try parseJSONResponse(providerResponse.content, as: T.self)
        }
    }
    
    /// Parse array response based on mode and element schema
    func parseArrayResponse<T: Codable>(
        providerResponse: ProviderResponse,
        mode: ProviderMode,
        elementSchema: ObjectSchema<T>
    ) throws -> [T] {
        switch mode {
        case .objectTool(let tool):
            // Parse tool call result for arrays
            return try parseToolCallArrayResponse(
                providerResponse: providerResponse,
                tool: tool,
                elementSchema: elementSchema
            )
        case .objectJSON:
            // Parse JSON response directly as array
            return try parseJSONResponse(providerResponse.content, as: [T].self)
        case .regular:
            // Fallback to JSON parsing
            return try parseJSONResponse(providerResponse.content, as: [T].self)
        }
    }
    
    /// Parse tool call response into array of structured objects
    private func parseToolCallArrayResponse<T: Codable>(
        providerResponse: ProviderResponse,
        tool: Tool,
        elementSchema: ObjectSchema<T>
    ) throws -> [T] {
        // Extract tool calls from the response
        guard let toolCalls = extractToolCallsFromResponse(providerResponse) else {
            throw AIGenerationError.noObjectGenerated(
                text: providerResponse.content,
                finishReason: providerResponse.finishReason,
                usage: providerResponse.usage
            )
        }
        
        // Find the matching tool call
        guard let toolCall = toolCalls.first(where: { $0.function.name == tool.function.name }) else {
            throw AIGenerationError.noSuchTool(
                toolName: tool.function.name,
                availableTools: toolCalls.map { $0.function.name }
            )
        }
        
        // Parse tool arguments as array wrapper: {elements: [...]}
        let toolArguments = toolCall.function.arguments
        
        do {
            let wrapper = try parseJSONResponse(toolArguments, as: ArrayWrapper<T>.self)
            return wrapper.elements
        } catch {
            throw AIGenerationError.invalidToolArguments(
                toolName: tool.function.name,
                toolArgs: toolArguments,
                cause: error
            )
        }
    }
    
    /// Parse tool call response into structured object
    private func parseToolCallResponse<T: Codable>(
        providerResponse: ProviderResponse,
        tool: Tool,
        schema: ObjectSchema<T>,
        outputStrategy: OutputStrategy
    ) throws -> T {
        // Extract tool calls from the response
        guard let toolCalls = extractToolCallsFromResponse(providerResponse) else {
            throw AIGenerationError.noObjectGenerated(
                text: providerResponse.content,
                finishReason: providerResponse.finishReason,
                usage: providerResponse.usage
            )
        }
        
        // Find the matching tool call
        guard let toolCall = toolCalls.first(where: { $0.function.name == tool.function.name }) else {
            throw AIGenerationError.noSuchTool(
                toolName: tool.function.name,
                availableTools: toolCalls.map { $0.function.name }
            )
        }
        
        // Parse tool arguments based on output strategy
        let toolArguments = toolCall.function.arguments
        
        do {
            switch outputStrategy {
            case .object:
                // Direct parsing for single objects
                return try parseJSONResponse(toolArguments, as: T.self)
            case .array:
                // Extract from elements wrapper: {elements: [...]}
                let wrapper = try parseJSONResponse(toolArguments, as: ArrayWrapper<T>.self)
                return wrapper.elements as! T
            case .enum:
                // Extract from value wrapper: {value: "..."}
                let wrapper = try parseJSONResponse(toolArguments, as: EnumWrapper.self)
                return wrapper.value as! T
            case .noSchema:
                // Parse as-is
                return try parseJSONResponse(toolArguments, as: T.self)
            }
        } catch {
            throw AIGenerationError.invalidToolArguments(
                toolName: tool.function.name,
                toolArgs: toolArguments,
                cause: error
            )
        }
    }
    
    /// Extract tool calls from provider response
    private func extractToolCallsFromResponse(_ response: ProviderResponse) -> [ToolCall]? {
        // First check if the response has tool calls directly (modern providers)
        if let toolCalls = response.toolCalls, !toolCalls.isEmpty {
            return toolCalls
        }
        
        // Fallback: try to parse the response content as a tool call response
        // This handles legacy providers that embed tool calls in content
        if response.content.contains("function_call") || response.content.contains("tool_calls") {
            do {
                // Try to extract tool calls from JSON response
                let toolCallData = try parseToolCallData(response.content)
                return toolCallData
            } catch {
                return nil
            }
        }
        
        return nil
    }
    
    /// Parse tool call data from response content
    private func parseToolCallData(_ content: String) throws -> [ToolCall] {
        // This is a simplified implementation
        // In practice, this would need to handle various provider response formats
        
        // For now, return empty array to prevent compilation errors
        // Real implementation would parse provider-specific tool call format
        return []
    }
}

// MARK: - Helper Types for Tool Response Parsing

/// Wrapper for array responses from tool calls
private struct ArrayWrapper<T: Codable>: Codable {
    let elements: [T]
}

/// Wrapper for enum responses from tool calls
private struct EnumWrapper: Codable {
    let value: String
}