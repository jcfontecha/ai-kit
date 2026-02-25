import Foundation
import AIKitProviders

public enum ToolCallRepairError: Error, Sendable {
  case noSuchTool(toolName: String)
  case invalidInput(toolName: String, details: String)
}

public struct ToolCallRepairContext: Sendable {
  public var system: SystemPrompt?
  public var messages: [ModelMessage]
  public var toolCall: ToolCall
  public var tools: ToolRegistry
  public var error: ToolCallRepairError

  public init(
    system: SystemPrompt?,
    messages: [ModelMessage],
    toolCall: ToolCall,
    tools: ToolRegistry,
    error: ToolCallRepairError
  ) {
    self.system = system
    self.messages = messages
    self.toolCall = toolCall
    self.tools = tools
    self.error = error
  }
}

public typealias ToolCallRepairFunction = @Sendable (ToolCallRepairContext) async throws -> ToolCall?
