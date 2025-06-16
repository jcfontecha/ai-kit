import Foundation

// MARK: - Tool Execution

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
internal extension AIClient {
    
    /// Execute a tool call and return the result.
    ///
    /// This method handles the execution of individual tool calls. If a custom tool executor
    /// was provided during initialization, it will be used. Otherwise, falls back to
    /// generic mock implementations for testing purposes.
    ///
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The result of the tool execution
    /// - Throws: Any errors from tool execution
    func executeToolCall(_ toolCall: ToolCall) async throws -> ToolResult {
        // Use caller-provided tool executor if available
        if let toolExecutor = self.toolExecutor {
            return try await toolExecutor(toolCall)
        }
        
        // No tool executor provided - this is an error in production
        throw AIGenerationError.toolExecutionFailed(
            toolName: toolCall.function.name,
            error: NSError(domain: "AIClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No tool executor provided. Tool execution requires a custom toolExecutor to be provided during AIClient initialization."
            ])
        )
    }
}