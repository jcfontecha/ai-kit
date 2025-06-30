import Foundation

// MARK: - Tool Execution

internal extension AIClient {
    
    /// Execute a tool call and return the result.
    ///
    /// This method handles the execution of individual tool calls. It looks for
    /// the matching tool in the provided tools array and calls its execute function.
    /// This follows Vercel AI SDK's pattern where tools have their own execute functions.
    ///
    /// - Parameters:
    ///   - toolCall: The tool call to execute
    ///   - tools: Array of available tools
    /// - Returns: The result of the tool execution
    /// - Throws: Any errors from tool execution
    func executeToolCall(_ toolCall: ToolCall, tools: [Tool]?) async throws -> ToolResult {
        // Find the matching tool
        guard let tool = tools?.first(where: { $0.function.name == toolCall.function.name }) else {
            throw AIGenerationError.noSuchTool(
                toolName: toolCall.function.name,
                availableTools: tools?.map { $0.function.name } ?? []
            )
        }
        
        // Check if the tool has an execute function
        guard let execute = tool.execute else {
            // Tool doesn't have an execute function - return error result
            return ToolResult.error(
                toolCallId: toolCall.id,
                error: "Tool '\(toolCall.function.name)' does not have an execute function"
            )
        }
        
        // Execute the tool
        return try await execute(toolCall)
    }
}