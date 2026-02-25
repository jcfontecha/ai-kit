import Foundation
import AIKitProviders

struct ParsedToolCall: Sendable, Equatable {
  var toolCallID: String
  var toolName: String
  var input: JSONValue
  var providerExecuted: Bool?
  var dynamic: Bool?
  var title: String?
  var providerMetadata: ProviderMetadata?
  var invalid: Bool
  var error: ToolCallError?

  init(
    toolCallID: String,
    toolName: String,
    input: JSONValue,
    providerExecuted: Bool? = nil,
    dynamic: Bool? = nil,
    title: String? = nil,
    providerMetadata: ProviderMetadata? = nil,
    invalid: Bool = false,
    error: ToolCallError? = nil
  ) {
    self.toolCallID = toolCallID
    self.toolName = toolName
    self.input = input
    self.providerExecuted = providerExecuted
    self.dynamic = dynamic
    self.title = title
    self.providerMetadata = providerMetadata
    self.invalid = invalid
    self.error = error
  }
}

struct ParseToolCallOptions: Sendable {
  var toolCall: ToolCall
  var tools: ToolRegistry?
  var repairToolCall: ToolCallRepairFunction?
  var messages: [ModelMessage]
  var system: SystemPrompt?

  init(
    toolCall: ToolCall,
    tools: ToolRegistry?,
    repairToolCall: ToolCallRepairFunction?,
    messages: [ModelMessage],
    system: SystemPrompt?
  ) {
    self.toolCall = toolCall
    self.tools = tools
    self.repairToolCall = repairToolCall
    self.messages = messages
    self.system = system
  }
}

func parseToolCall(_ options: ParseToolCallOptions) async -> ParsedToolCall {
  return await parseToolCall(options, allowRepair: true)
}

private func parseToolCall(_ options: ParseToolCallOptions, allowRepair: Bool) async -> ParsedToolCall {
  let toolCall = options.toolCall
  let tools = options.tools
  let toolName = toolCall.toolName
  let toolCallID = toolCall.toolCallID

  // Dynamic tool calls (unknown schema/typed tool) should still be surfaced to the client
  // even when the tool registry is not available. This matches "dynamic tools" semantics.
  if toolCall.dynamic == true {
    let input = parseInputJSONResult(toolCall.inputJSON).value ?? .object([:])
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: input,
      providerExecuted: toolCall.providerExecuted,
      dynamic: true,
      title: toolCall.title,
      providerMetadata: toolCall.providerMetadata
    )
  }

  // Provider-executed tool calls may be unknown to the local tool registry.
  // Treat them as dynamic so they are surfaced instead of converted to invalid no-such-tool errors.
  if toolCall.providerExecuted == true,
     (tools?.toolBox(named: toolName) == nil) {
    let input = parseInputJSONResult(toolCall.inputJSON).value ?? .object([:])
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: input,
      providerExecuted: true,
      dynamic: toolCall.dynamic ?? true,
      title: toolCall.title,
      providerMetadata: toolCall.providerMetadata
    )
  }

  guard let tools, let toolBox = tools.toolBox(named: toolName) else {
    let message: String
    if tools == nil || tools?.isEmpty == true {
      message = "Model tried to call unavailable tool '\(toolName)'. No tools are available."
    } else {
      let available = tools?.allToolNames.joined(separator: ", ") ?? ""
      message = "Model tried to call unavailable tool '\(toolName)'. Available tools: \(available)."
    }
    let input = parseInputJSONResult(toolCall.inputJSON).value ?? .object([:])
    let error = ToolCallError.noSuchTool(.init(message: message))
    if allowRepair, options.repairToolCall != nil {
      return await attemptRepairWithoutTool(
        options: options,
        error: error
      )
    }
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: input,
      providerExecuted: toolCall.providerExecuted,
      dynamic: true,
      title: toolCall.title,
      providerMetadata: toolCall.providerMetadata,
      invalid: true,
      error: error
    )
  }

  let title = toolCall.title ?? toolBox.tool.title

  let parseResult = parseInputJSONResult(toolCall.inputJSON)
  guard let parsedInput = parseResult.value else {
    let errorMessage = parseResult.errorMessage ?? "Unknown error"
    let error = InvalidToolInputError(
      message: "Invalid input for tool \(toolName): JSON parsing failed: Text: \(toolCall.inputJSON). Error message: \(errorMessage)"
    )
    if allowRepair, options.repairToolCall != nil {
      return await attemptRepair(
        options: options,
        toolBox: toolBox,
        toolName: toolName,
        error: .invalidInput(error),
        allowRepair: allowRepair
      )
    }
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: .string(toolCall.inputJSON),
      providerExecuted: toolCall.providerExecuted,
      dynamic: toolCall.dynamic,
      title: title,
      providerMetadata: toolCall.providerMetadata,
      invalid: true,
      error: .invalidInput(error)
    )
  }

  do {
    _ = try toolBox.decodeInput(from: parsedInput)
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: parsedInput,
      providerExecuted: toolCall.providerExecuted,
      dynamic: toolCall.dynamic,
      title: title,
      providerMetadata: toolCall.providerMetadata
    )
  } catch {
    let valueString = OutputParsing.encodeJSONValue(parsedInput)
    let message = "Invalid input for tool \(toolName): Type validation failed: Value: \(valueString ?? ""). Error message: \(error)"
    let invalid = InvalidToolInputError(message: message)
    if allowRepair, options.repairToolCall != nil {
      return await attemptRepair(
        options: options,
        toolBox: toolBox,
        toolName: toolName,
        error: .invalidInput(invalid),
        allowRepair: allowRepair
      )
    }
    return ParsedToolCall(
      toolCallID: toolCallID,
      toolName: toolName,
      input: parsedInput,
      providerExecuted: toolCall.providerExecuted,
      dynamic: toolCall.dynamic,
      title: title,
      providerMetadata: toolCall.providerMetadata,
      invalid: true,
      error: .invalidInput(invalid)
    )
  }
}

private func attemptRepair(
  options: ParseToolCallOptions,
  toolBox: any AnyToolBoxProtocol,
  toolName: String,
  error: ToolCallError,
  allowRepair: Bool
) async -> ParsedToolCall {
  guard let repair = options.repairToolCall else {
    return ParsedToolCall(
      toolCallID: options.toolCall.toolCallID,
      toolName: options.toolCall.toolName,
      input: .string(options.toolCall.inputJSON),
      providerExecuted: options.toolCall.providerExecuted,
      dynamic: options.toolCall.dynamic,
      title: options.toolCall.title ?? toolBox.tool.title,
      providerMetadata: options.toolCall.providerMetadata,
      invalid: true,
      error: error
    )
  }

  do {
    if let repaired = try await repair(
      .init(
        system: options.system,
        messages: options.messages,
        toolCall: options.toolCall,
        tools: options.tools ?? .init(),
        error: toolCallRepairError(from: error, toolName: toolName)
      )
    ) {
      return await parseToolCall(
        .init(
          toolCall: repaired,
          tools: options.tools,
          repairToolCall: options.repairToolCall,
          messages: options.messages,
          system: options.system
        ),
        allowRepair: false
      )
    }
  } catch {
    let failed = ToolCallRepairFailedError(message: "Error repairing tool call: \(error)")
    return ParsedToolCall(
      toolCallID: options.toolCall.toolCallID,
      toolName: options.toolCall.toolName,
      input: .string(options.toolCall.inputJSON),
      providerExecuted: options.toolCall.providerExecuted,
      dynamic: options.toolCall.dynamic,
      title: options.toolCall.title ?? toolBox.tool.title,
      providerMetadata: options.toolCall.providerMetadata,
      invalid: true,
      error: .repairFailed(failed)
    )
  }

  return ParsedToolCall(
    toolCallID: options.toolCall.toolCallID,
    toolName: options.toolCall.toolName,
    input: .string(options.toolCall.inputJSON),
    providerExecuted: options.toolCall.providerExecuted,
    dynamic: options.toolCall.dynamic,
    title: options.toolCall.title ?? toolBox.tool.title,
    providerMetadata: options.toolCall.providerMetadata,
    invalid: true,
    error: error
  )
}

private func attemptRepairWithoutTool(
  options: ParseToolCallOptions,
  error: ToolCallError
) async -> ParsedToolCall {
  guard let repair = options.repairToolCall else {
    return ParsedToolCall(
      toolCallID: options.toolCall.toolCallID,
      toolName: options.toolCall.toolName,
      input: .string(options.toolCall.inputJSON),
      providerExecuted: options.toolCall.providerExecuted,
      dynamic: options.toolCall.dynamic,
      title: options.toolCall.title,
      providerMetadata: options.toolCall.providerMetadata,
      invalid: true,
      error: error
    )
  }

  do {
    if let repaired = try await repair(
      .init(
        system: options.system,
        messages: options.messages,
        toolCall: options.toolCall,
        tools: options.tools ?? .init(),
        error: toolCallRepairError(from: error, toolName: options.toolCall.toolName)
      )
    ) {
      return await parseToolCall(
        .init(
          toolCall: repaired,
          tools: options.tools,
          repairToolCall: options.repairToolCall,
          messages: options.messages,
          system: options.system
        ),
        allowRepair: false
      )
    }
  } catch {
    let failed = ToolCallRepairFailedError(message: "Error repairing tool call: \(error)")
    return ParsedToolCall(
      toolCallID: options.toolCall.toolCallID,
      toolName: options.toolCall.toolName,
      input: .string(options.toolCall.inputJSON),
      providerExecuted: options.toolCall.providerExecuted,
      dynamic: options.toolCall.dynamic,
      title: options.toolCall.title,
      providerMetadata: options.toolCall.providerMetadata,
      invalid: true,
      error: .repairFailed(failed)
    )
  }

  return ParsedToolCall(
    toolCallID: options.toolCall.toolCallID,
    toolName: options.toolCall.toolName,
    input: .string(options.toolCall.inputJSON),
    providerExecuted: options.toolCall.providerExecuted,
    dynamic: options.toolCall.dynamic,
    title: options.toolCall.title,
    providerMetadata: options.toolCall.providerMetadata,
    invalid: true,
    error: error
  )
}

private func toolCallRepairError(from error: ToolCallError, toolName: String) -> ToolCallRepairError {
  switch error {
  case .noSuchTool:
    return .noSuchTool(toolName: toolName)
  case .invalidInput(let invalid):
    return .invalidInput(toolName: toolName, details: invalid.message)
  case .repairFailed:
    return .invalidInput(toolName: toolName, details: error.message)
  }
}

private func parseInputJSONResult(_ input: String) -> (value: JSONValue?, errorMessage: String?) {
  let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return (.object([:]), nil) }
  guard let data = trimmed.data(using: .utf8) else {
    return (nil, "Input was not valid UTF-8.")
  }
  do {
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return (JSONValue.from(object), nil)
  } catch {
    return (nil, "\(error)")
  }
}
