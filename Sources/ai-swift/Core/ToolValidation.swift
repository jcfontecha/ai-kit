import Foundation

// MARK: - Tool Validation

/// Tool validation utilities following Vercel AI SDK patterns
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public struct ToolValidation {
    
    /// Validate that a tool exists in the available tools
    /// - Parameters:
    ///   - toolName: Name of the tool to validate
    ///   - availableTools: Array of available tools
    /// - Throws: AIGenerationError.noSuchTool if tool doesn't exist
    public static func validateToolExists(toolName: String, availableTools: [Tool]) throws {
        let toolNames = availableTools.map { $0.function.name }
        
        if !toolNames.contains(toolName) {
            throw AIGenerationError.noSuchTool(
                toolName: toolName,
                availableTools: toolNames
            )
        }
    }
    
    /// Validate tool call arguments against the tool's parameter schema
    /// - Parameters:
    ///   - toolCall: The tool call to validate
    ///   - tool: The tool definition with schema
    /// - Throws: AIGenerationError.invalidToolArguments if validation fails
    public static func validateToolArguments(toolCall: ToolCall, tool: Tool) throws {
        do {
            // First, try to parse the arguments as JSON
            guard let argumentsData = toolCall.function.arguments.data(using: .utf8) else {
                throw AIGenerationError.invalidToolArguments(
                    toolName: toolCall.function.name,
                    toolArgs: toolCall.function.arguments,
                    cause: NSError(domain: "ToolValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Arguments are not valid UTF-8"])
                )
            }
            
            let _ = try JSONSerialization.jsonObject(with: argumentsData, options: [])
            
            // Note: Comprehensive JSON schema validation is available via SchemaValidator protocol
            // but requires a validator implementation to be provided. For now, we validate JSON syntax only.
            // To add schema validation, implement SchemaValidator and call:
            // let result = try validator.validate(argumentsData, against: tool.function.parameters)
            
        } catch let jsonError {
            throw AIGenerationError.invalidToolArguments(
                toolName: toolCall.function.name,
                toolArgs: toolCall.function.arguments,
                cause: jsonError
            )
        }
    }
    
    /// Validate tool call structure
    /// - Parameter toolCall: The tool call to validate
    /// - Throws: AIGenerationError.invalidToolArguments for structural issues
    public static func validateToolCallStructure(toolCall: ToolCall) throws {
        // Validate tool call has required fields
        if toolCall.function.name.isEmpty {
            throw AIGenerationError.invalidToolArguments(
                toolName: toolCall.function.name,
                toolArgs: toolCall.function.arguments,
                cause: NSError(domain: "ToolValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tool name cannot be empty"])
            )
        }
        
        if toolCall.id.isEmpty {
            throw AIGenerationError.invalidToolArguments(
                toolName: toolCall.function.name,
                toolArgs: toolCall.function.arguments,
                cause: NSError(domain: "ToolValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tool call ID cannot be empty"])
            )
        }
    }
    
    /// Comprehensive tool call validation
    /// - Parameters:
    ///   - toolCall: The tool call to validate
    ///   - availableTools: Array of available tools
    /// - Throws: Various AIGenerationError cases for different validation failures
    public static func validateToolCall(toolCall: ToolCall, availableTools: [Tool]) throws {
        // 1. Validate structure
        try validateToolCallStructure(toolCall: toolCall)
        
        // 2. Validate tool exists
        try validateToolExists(toolName: toolCall.function.name, availableTools: availableTools)
        
        // 3. Find the tool and validate arguments
        guard let tool = availableTools.first(where: { $0.function.name == toolCall.function.name }) else {
            // This should not happen after validateToolExists, but safety check
            throw AIGenerationError.noSuchTool(
                toolName: toolCall.function.name,
                availableTools: availableTools.map { $0.function.name }
            )
        }
        
        // 4. Validate arguments against schema
        try validateToolArguments(toolCall: toolCall, tool: tool)
    }
    
    /// Create a ToolExecutionError from a tool call and underlying error
    /// - Parameters:
    ///   - toolCall: The tool call that failed
    ///   - error: The underlying execution error
    /// - Returns: AIGenerationError.toolExecutionError with proper context
    public static func createToolExecutionError(toolCall: ToolCall, error: Error) -> AIGenerationError {
        return AIGenerationError.toolExecutionError(
            toolName: toolCall.function.name,
            toolArgs: toolCall.function.arguments,
            toolCallId: toolCall.id,
            cause: error
        )
    }
}


// MARK: - Tool Call Extensions

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public extension ToolCall {
    /// Validate this tool call against available tools
    /// - Parameter availableTools: Array of available tools
    /// - Throws: AIGenerationError for validation failures
    func validate(against availableTools: [Tool]) throws {
        try ToolValidation.validateToolCall(toolCall: self, availableTools: availableTools)
    }
}

public extension Array where Element == Tool {
    /// Find a tool by name
    /// - Parameter name: Tool name to search for
    /// - Returns: The tool if found, nil otherwise
    func tool(named name: String) -> Tool? {
        return first { $0.function.name == name }
    }
    
    /// Get all tool names
    var toolNames: [String] {
        return map { $0.function.name }
    }
}