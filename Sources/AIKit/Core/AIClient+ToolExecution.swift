import Foundation

// MARK: - Tool Execution

internal extension AIClient {
    
    /// Execute a tool call and return the result.
    ///
    /// This method handles the execution of individual tool calls. It uses the provided
    /// tool executor (parameter), falls back to the instance's tool executor, or throws
    /// an error if no executor is available.
    ///
    /// - Parameters:
    ///   - toolCall: The tool call to execute
    ///   - toolExecutor: Optional tool executor to use for this specific call
    /// - Returns: The result of the tool execution
    /// - Throws: Any errors from tool execution
    func executeToolCall(_ toolCall: ToolCall, toolExecutor: ToolExecutor? = nil) async throws -> ToolResult {
        // Use provided tool executor first, then instance executor
        let executor = toolExecutor ?? self.toolExecutor
        
        if let executor = executor {
            return try await executor(toolCall)
        }
        
        // No tool executor provided - this is an error in production
        throw AIGenerationError.toolExecutionFailed(
            toolName: toolCall.function.name,
            error: NSError(domain: "AIClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No tool executor provided. Tool execution requires a custom toolExecutor to be provided either during AIClient initialization or as a parameter to generateText."
            ])
        )
    }
}