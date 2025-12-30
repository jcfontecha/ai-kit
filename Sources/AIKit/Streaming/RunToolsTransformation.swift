import Foundation
import AIKitProviders

struct RunToolsTransformationOptions: Sendable {
  var generateID: @Sendable () -> String
  var generatorStream: AsyncThrowingStream<ModelStreamPart, Error>
  var tools: ToolRegistry?
  var messages: [ModelMessage]
  var system: SystemPrompt?
  var repairToolCall: ToolCallRepairFunction?
  var experimentalContext: AnySendable?

  init(
    generateID: @escaping @Sendable () -> String,
    generatorStream: AsyncThrowingStream<ModelStreamPart, Error>,
    tools: ToolRegistry?,
    messages: [ModelMessage],
    system: SystemPrompt?,
    repairToolCall: ToolCallRepairFunction?,
    experimentalContext: AnySendable?
  ) {
    self.generateID = generateID
    self.generatorStream = generatorStream
    self.tools = tools
    self.messages = messages
    self.system = system
    self.repairToolCall = repairToolCall
    self.experimentalContext = experimentalContext
  }
}

func runToolsTransformation(
  _ options: RunToolsTransformationOptions
) -> AsyncThrowingStream<TextStreamPart, Error> {
  AsyncThrowingStream(TextStreamPart.self) { continuation in
    Task {
      var pending: [Task<Void, Never>] = []
      var toolCallsByID: [String: ToolCall] = [:]
      var toolInputsByID: [String: JSONValue] = [:]

      do {
        for try await part in options.generatorStream {
          switch part {
          case .streamStart(let warnings):
            continuation.yield(.start)
            continuation.yield(.startStep(warnings: warnings))
          case .startStep(let request, let warnings):
            continuation.yield(.startStep(request: request, warnings: warnings))
          case .textStart(let id, let providerMetadata):
            continuation.yield(.textStart(id: id, providerMetadata: providerMetadata))
          case .textDelta(let id, let text, let providerMetadata):
            continuation.yield(.textDelta(id: id, text: text, providerMetadata: providerMetadata))
          case .textEnd(let id, let providerMetadata):
            continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))
          case .reasoningStart(let id, let providerMetadata):
            continuation.yield(.reasoningStart(id: id, providerMetadata: providerMetadata))
          case .reasoningDelta(let id, let text, let providerMetadata):
            continuation.yield(.reasoningDelta(id: id, text: text, providerMetadata: providerMetadata))
          case .reasoningEnd(let id, let providerMetadata):
            continuation.yield(.reasoningEnd(id: id, providerMetadata: providerMetadata))
          case .toolInputStart(let id, let toolName, let providerMetadata, let providerExecuted, let dynamic, let title):
            continuation.yield(
              .toolInputStart(
                id: id,
                toolName: toolName,
                providerMetadata: providerMetadata,
                providerExecuted: providerExecuted,
                dynamic: dynamic,
                title: title
              )
            )
          case .toolInputDelta(let id, let delta, let providerMetadata):
            continuation.yield(.toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))
          case .toolInputEnd(let id, let providerMetadata):
            continuation.yield(.toolInputEnd(id: id, providerMetadata: providerMetadata))
          case .source(let source):
            continuation.yield(.source(source))
          case .file(let file):
            continuation.yield(.file(file))
          case .toolApprovalRequest(let request):
            if let toolCall = toolCallsByID[request.toolCallID] {
              continuation.yield(
                .toolApprovalRequest(
                  .init(
                    approvalID: request.approvalID,
                    toolCallID: request.toolCallID,
                    toolCall: toolCall
                  )
                )
              )
            } else {
              let message =
                "Tool call \"\(request.toolCallID)\" not found for approval request \"\(request.approvalID)\"."
              continuation.yield(.error(message))
            }
          case .toolResult(let result):
            var enriched = result
            if enriched.input == nil, let input = toolInputsByID[result.toolCallID] {
              enriched.input = input
            }
            continuation.yield(.toolResult(enriched))
          case .toolError(let error):
            var enriched = error
            if enriched.input == nil, let input = toolInputsByID[error.toolCallID] {
              enriched.input = input
            }
            continuation.yield(.toolError(enriched))
          case .toolOutputDenied(let denied):
            continuation.yield(.toolOutputDenied(denied))
          case .toolCall(let call):
            await handleToolCall(
              call,
              options: options,
              pending: &pending,
              toolCallsByID: &toolCallsByID,
              toolInputsByID: &toolInputsByID,
              continuation: continuation
            )
          case .finish(let finishReason, let usage, let providerMetadata):
            for task in pending { await task.value }
            continuation.yield(.finish(finishReason: finishReason, totalUsage: usage))
            if let providerMetadata {
              continuation.yield(.raw(.object(providerMetadata.mapValues { $0 })))
            }
          case .finishStep(let response, let usage, let finishReason, let rawFinishReason, let providerMetadata):
            continuation.yield(
              .finishStep(
                response: response,
                usage: usage,
                finishReason: finishReason,
                rawFinishReason: rawFinishReason,
                providerMetadata: providerMetadata
              )
            )
          case .responseMetadata:
            break
          case .raw(let value):
            continuation.yield(.raw(value))
          case .error(let error):
            continuation.yield(.error(error.message))
          }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }
}

private func handleToolCall(
  _ call: ToolCall,
  options: RunToolsTransformationOptions,
  pending: inout [Task<Void, Never>],
  toolCallsByID: inout [String: ToolCall],
  toolInputsByID: inout [String: JSONValue],
  continuation: AsyncThrowingStream<TextStreamPart, Error>.Continuation
) async {
  let parsed = await parseToolCall(
    .init(
      toolCall: call,
      tools: options.tools,
      repairToolCall: options.repairToolCall,
      messages: options.messages,
      system: options.system
    )
  )

  let outputCall = ToolCall(
    toolCallID: parsed.toolCallID,
    toolName: parsed.toolName,
    inputJSON: call.inputJSON,
    input: parsed.input,
    invalid: parsed.invalid ? true : nil,
    error: parsed.error?.message,
    providerExecuted: parsed.providerExecuted,
    dynamic: parsed.dynamic,
    title: parsed.title,
    providerMetadata: parsed.providerMetadata
  )

  toolCallsByID[outputCall.toolCallID] = outputCall

  // Fire onInputAvailable before emitting the tool call.
  if let tools = options.tools,
     let toolBox = tools.toolBox(named: parsed.toolName) {
    let context = ToolContext(
      toolCallID: parsed.toolCallID,
      messages: options.messages,
      experimentalContext: options.experimentalContext
    )
    if let inputAny = try? toolBox.decodeInput(from: parsed.input) {
      await toolBox.onInputAvailable(inputAny, context: context)
    }
  }

  continuation.yield(.toolCall(outputCall))

  guard parsed.invalid == false else {
    if let error = parsed.error {
      continuation.yield(.toolError(
        ToolError(
          toolCallID: parsed.toolCallID,
          toolName: parsed.toolName,
          inputJSON: call.inputJSON,
          input: parsed.input,
          error: error.message,
          providerExecuted: parsed.providerExecuted,
          dynamic: parsed.dynamic ?? true,
          title: parsed.title,
          providerMetadata: parsed.providerMetadata
        )
      ))
    }
    return
  }

  if parsed.providerExecuted == true {
    return
  }

  guard let tools = options.tools,
        let toolBox = tools.toolBox(named: parsed.toolName),
        let inputAny = try? toolBox.decodeInput(from: parsed.input)
  else {
    return
  }

  let context = ToolContext(
    toolCallID: parsed.toolCallID,
    messages: options.messages,
    experimentalContext: options.experimentalContext
  )

  if let needsApproval = await toolBox.needsApproval(inputAny, context: context), needsApproval {
    let approvalID = options.generateID()
    continuation.yield(
      .toolApprovalRequest(
        .init(
          approvalID: approvalID,
          toolCallID: parsed.toolCallID,
          toolCall: outputCall
        )
      )
    )
    return
  }

  toolInputsByID[parsed.toolCallID] = parsed.input

  if parsed.providerExecuted == true {
    return
  }

  guard let execution = try? await toolBox.execute(inputAny, context: context) else {
    return
  }

  let task: Task<Void, Never> = Task {
    do {
      switch execution {
      case .final(let output):
        let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
        continuation.yield(
          .toolResult(
            ToolResult(
              toolCallID: parsed.toolCallID,
              toolName: parsed.toolName,
              inputJSON: call.inputJSON,
              input: parsed.input,
              output: jsonValue,
              preliminary: false,
              providerExecuted: parsed.providerExecuted,
              dynamic: parsed.dynamic ?? false,
              title: parsed.title,
              providerMetadata: parsed.providerMetadata
            )
          )
        )
      case .streaming(let stream):
        for try await progress in stream {
          switch progress {
          case .preliminary(let output):
            let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
            continuation.yield(
              .toolResult(
                ToolResult(
                  toolCallID: parsed.toolCallID,
                  toolName: parsed.toolName,
                  inputJSON: call.inputJSON,
                  input: parsed.input,
                  output: jsonValue,
                  preliminary: true,
                  providerExecuted: parsed.providerExecuted,
                  dynamic: parsed.dynamic ?? false,
                  title: parsed.title,
                  providerMetadata: parsed.providerMetadata
                )
              )
            )
          case .final(let output):
            let jsonValue = (try? toolBox.encodeOutput(output)) ?? .null
            continuation.yield(
              .toolResult(
                ToolResult(
                  toolCallID: parsed.toolCallID,
                  toolName: parsed.toolName,
                  inputJSON: call.inputJSON,
                  input: parsed.input,
                  output: jsonValue,
                  preliminary: false,
                  providerExecuted: parsed.providerExecuted,
                  dynamic: parsed.dynamic ?? false,
                  title: parsed.title,
                  providerMetadata: parsed.providerMetadata
                )
              )
            )
          }
        }
      }
    } catch {
      continuation.yield(.toolError(
        ToolError(
          toolCallID: parsed.toolCallID,
          toolName: parsed.toolName,
          inputJSON: call.inputJSON,
          input: parsed.input,
          error: "Tool execution failed: \(error)",
          providerExecuted: parsed.providerExecuted,
          dynamic: parsed.dynamic ?? false,
          title: parsed.title,
          providerMetadata: parsed.providerMetadata
        )
      ))
    }
  }

  pending.append(task)
}
