import Foundation
import AIKitProviders

struct OpenAIResponsesConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
}

struct OpenAIResponsesLanguageModel: LanguageModel, Sendable {
  let id: String
  let capabilities: ModelCapabilities = []
  let supportedURLs: SupportedURLPatterns = [
    "image/*": [
      URLPattern("^https?://.+\\.(jpg|jpeg|png|gif|webp)$", options: .caseInsensitive),
    ],
    "application/*": [
      URLPattern("^https?://.+$"),
    ],
  ]

  let modelId: OpenAIResponsesModelID
  let options: OpenAIResponsesProviderOptions
  let config: OpenAIResponsesConfig

  init(modelId: OpenAIResponsesModelID, options: OpenAIResponsesProviderOptions, config: OpenAIResponsesConfig) {
    self.modelId = modelId
    self.options = options
    self.config = config
    self.id = modelId.rawValue
  }

  private var modelCapabilities: OpenAILanguageModelCapabilities {
    getOpenAILanguageModelCapabilities(
      modelID: modelId.rawValue,
      forceReasoning: options.forceReasoning,
      systemMessageModeOverride: options.systemMessageMode
    )
  }

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    let args = try buildArgs(from: request)
    let bodyValue = JSONValue.object(args)
    let data = try OpenAIJSON.encodeToData(bodyValue)

    var urlRequest = URLRequest(url: URL(string: config.url("/responses"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)

    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: responseData)
    }

    let responseValue = try OpenAIJSON.decoder.decode(OpenAIResponsesEnvelope.self, from: responseData)
    if let error = responseValue.error {
      throw OpenAIAPIError(message: error.message, statusCode: 200)
    }

    var content: [ModelContentPart] = []
    var hasToolCall = false

    for item in responseValue.output ?? [] {
      switch item.type {
      case "message":
        for part in item.content ?? [] {
          if part.type == "output_text", let text = part.text, text.isEmpty == false {
            content.append(.text(text))
          }
        }
      case "reasoning":
        let summaryText = (item.summary ?? []).compactMap { $0.text }.joined()
        if summaryText.isEmpty == false {
          content.append(.reasoning(summaryText))
        }
      case "function_call":
        hasToolCall = true
        let callID = item.callID ?? item.id ?? UUID().uuidString
        let inputJSON = item.arguments ?? "{}"
        content.append(
          .toolCall(
            ToolCall(
              toolCallID: callID,
              toolName: item.name ?? "",
              inputJSON: inputJSON,
              input: try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)),
              providerMetadata: nil
            )
          )
        )
      default:
        continue
      }
    }

    let usage = mapUsage(from: responseValue.usage)
    let finishReason = mapResponsesFinishReason(
      status: responseValue.status,
      incompleteReason: responseValue.incompleteDetails?.reason,
      hasToolCall: hasToolCall
    )
    let responseBody = try? OpenAIJSON.decoder.decode(JSONValue.self, from: responseData)

    return ModelResponse(
      content: content,
      finishReason: finishReason,
      rawFinishReason: responseValue.status,
      usage: usage,
      warnings: [],
      request: .init(body: bodyValue),
      response: .init(
        id: responseValue.id ?? "",
        modelID: responseValue.model ?? "",
        timestamp: Date(),
        headers: response.allHeaderFields as? [String: String],
        body: responseBody
      ),
      providerMetadata: nil
    )
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      Task {
        do {
          var args = try buildArgs(from: request)
          args["stream"] = .bool(true)

          let bodyValue = JSONValue.object(args)
          let data = try OpenAIJSON.encodeToData(bodyValue)

          var urlRequest = URLRequest(url: URL(string: config.url("/responses"))!)
          urlRequest.httpMethod = "POST"
          urlRequest.httpBody = data

          let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
          for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

          let (byteStream, response) = try await config.transport.bytes(for: urlRequest)

          guard response.statusCode == 200 else {
            throw await openAIAPIError(statusCode: response.statusCode, bytes: byteStream)
          }

          let sseStream = parseSSELines(byteStream)

          var finishReason: FinishReason = .other
          var usage = Usage(inputTokens: .init(), outputTokens: .init())
          var hasToolCall = false

          // Tracks active text blocks by output index, reasoning blocks, and function-call argument buffers.
          var activeTextIds: [Int: String] = [:]
          var activeReasoningIds: [Int: String] = [:]
          var functionCalls: [String: OpenAIResponsesFunctionCallBuffer] = [:]

          for try await payload in sseStream {
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8) else { continue }
            let event: OpenAIResponsesStreamEvent
            do {
              event = try OpenAIJSON.decoder.decode(OpenAIResponsesStreamEvent.self, from: chunkData)
            } catch {
              finishReason = .error
              continuation.yield(.error(.init(message: error.localizedDescription)))
              break
            }

            switch event.type {
            case "response.created", "response.in_progress":
              if let id = event.response?.id {
                continuation.yield(.responseMetadata(.init(id: id)))
              }
              if let model = event.response?.model {
                continuation.yield(.responseMetadata(.init(modelID: model)))
              }

            case "response.output_item.added":
              guard let item = event.item, let index = event.outputIndex else { break }
              if item.type == "function_call" {
                let callID = item.callID ?? item.id ?? UUID().uuidString
                let buffer = OpenAIResponsesFunctionCallBuffer(
                  callID: callID,
                  name: item.name ?? "",
                  arguments: ""
                )
                if let key = item.id { functionCalls[key] = buffer }
                continuation.yield(.toolInputStart(id: callID, toolName: item.name ?? ""))
              } else if item.type == "reasoning" {
                let id = item.id ?? UUID().uuidString
                activeReasoningIds[index] = id
                continuation.yield(.reasoningStart(id: id))
              }

            case "response.content_part.added":
              guard let index = event.outputIndex, let part = event.part else { break }
              if part.type == "output_text" {
                let id = event.itemId ?? UUID().uuidString
                activeTextIds[index] = id
                continuation.yield(.textStart(id: id))
              }

            case "response.output_text.delta":
              guard let index = event.outputIndex, let delta = event.delta else { break }
              let id = activeTextIds[index] ?? (event.itemId ?? UUID().uuidString)
              if activeTextIds[index] == nil {
                activeTextIds[index] = id
                continuation.yield(.textStart(id: id))
              }
              continuation.yield(.textDelta(id: id, text: delta))

            case "response.output_text.done":
              guard let index = event.outputIndex, let id = activeTextIds[index] else { break }
              continuation.yield(.textEnd(id: id))
              activeTextIds[index] = nil

            case "response.reasoning_summary_text.delta":
              guard let index = event.outputIndex, let delta = event.delta else { break }
              let id = activeReasoningIds[index] ?? (event.itemId ?? UUID().uuidString)
              if activeReasoningIds[index] == nil {
                activeReasoningIds[index] = id
                continuation.yield(.reasoningStart(id: id))
              }
              continuation.yield(.reasoningDelta(id: id, text: delta))

            case "response.reasoning_summary_text.done":
              guard let index = event.outputIndex, let id = activeReasoningIds[index] else { break }
              continuation.yield(.reasoningEnd(id: id))
              activeReasoningIds[index] = nil

            case "response.function_call_arguments.delta":
              guard let key = event.itemId, let delta = event.delta else { break }
              guard var buffer = functionCalls[key] else { break }
              buffer.arguments += delta
              functionCalls[key] = buffer
              continuation.yield(.toolInputDelta(id: buffer.callID, delta: delta))

            case "response.function_call_arguments.done":
              guard let key = event.itemId, var buffer = functionCalls[key] else { break }
              if let arguments = event.arguments { buffer.arguments = arguments }
              functionCalls[key] = buffer
              hasToolCall = true
              continuation.yield(.toolInputEnd(id: buffer.callID))
              let inputJSON = OpenAIJSON.isParsableJSON(buffer.arguments) ? buffer.arguments : "{}"
              continuation.yield(
                .toolCall(
                  ToolCall(
                    toolCallID: buffer.callID,
                    toolName: buffer.name,
                    inputJSON: inputJSON,
                    input: try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)),
                    providerMetadata: nil
                  )
                )
              )
              buffer.sent = true
              functionCalls[key] = buffer

            case "response.output_item.done":
              // Reasoning/text blocks are closed by their own .done events; nothing else required here.
              break

            case "response.completed", "response.incomplete":
              if let chunkUsage = event.response?.usage {
                usage = mapUsage(from: chunkUsage)
              }
              finishReason = mapResponsesFinishReason(
                status: event.response?.status ?? (event.type == "response.completed" ? "completed" : "incomplete"),
                incompleteReason: event.response?.incompleteDetails?.reason,
                hasToolCall: hasToolCall
              )

            case "response.failed", "response.error":
              finishReason = .error
              let message = event.response?.error?.message ?? event.message ?? "Response failed"
              continuation.yield(.error(.init(message: message)))

            default:
              break
            }
          }

          // Close any text/reasoning blocks the stream left open.
          for (_, id) in activeTextIds { continuation.yield(.textEnd(id: id)) }
          for (_, id) in activeReasoningIds { continuation.yield(.reasoningEnd(id: id)) }

          continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: nil))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func buildArgs(from request: ModelRequest) throws -> [String: JSONValue] {
    let capabilities = modelCapabilities
    let input = try convertToOpenAIResponsesInput(
      request.messages,
      systemMessageMode: capabilities.systemMessageMode
    )

    var args: [String: JSONValue] = [
      "model": .string(modelId.rawValue),
      "input": .array(input.items),
    ]

    if let instructions = options.instructions ?? input.instructions {
      args["instructions"] = .string(instructions)
    }

    if let previousResponseID = options.previousResponseID {
      args["previous_response_id"] = .string(previousResponseID)
    }
    if let conversation = options.conversation {
      args["conversation"] = .string(conversation)
    }
    if let store = options.store {
      args["store"] = .bool(store)
    }
    if let truncation = options.truncation {
      args["truncation"] = .string(truncation.rawValue)
    }
    if let include = options.include {
      args["include"] = .array(include.map(JSONValue.string))
    }
    if let maxToolCalls = options.maxToolCalls {
      args["max_tool_calls"] = .number(Double(maxToolCalls))
    }
    if let serviceTier = options.serviceTier {
      args["service_tier"] = .string(serviceTier.rawValue)
    }
    if let metadata = options.metadata {
      args["metadata"] = .object(metadata.mapValues(JSONValue.string))
    }
    if let promptCacheKey = options.promptCacheKey {
      args["prompt_cache_key"] = .string(promptCacheKey)
    }
    if let safetyIdentifier = options.safetyIdentifier {
      args["safety_identifier"] = .string(safetyIdentifier)
    }
    if let parallelToolCalls = options.parallelToolCalls {
      args["parallel_tool_calls"] = .bool(parallelToolCalls)
    }
    if let user = options.user {
      args["user"] = .string(user)
    }

    if options.reasoningEffort != nil || options.reasoningSummary != nil {
      var reasoning: [String: JSONValue] = [:]
      if let effort = options.reasoningEffort {
        reasoning["effort"] = .string(effort.rawValue)
      }
      if let summary = options.reasoningSummary {
        reasoning["summary"] = .string(summary)
      }
      args["reasoning"] = .object(reasoning)
    }
    if let verbosity = options.textVerbosity {
      args["text"] = .object(["verbosity": .string(verbosity.rawValue)])
    }

    if let maxOutputTokens = request.settings.maxOutputTokens {
      args["max_output_tokens"] = .number(Double(maxOutputTokens))
    }
    if capabilities.supportsNonReasoningParameters || capabilities.isReasoningModel == false {
      if let temperature = request.settings.temperature {
        args["temperature"] = .number(temperature)
      }
      if let topP = request.settings.topP {
        args["top_p"] = .number(topP)
      }
    }

    if let responseFormatValue = responseFormat(for: request.responseFormat) {
      args["text"] = mergeTextFormat(existing: args["text"], format: responseFormatValue)
    }

    if let tools = mapTools(request.tools) {
      args["tools"] = tools
      if request.toolChoice != .auto {
        args["tool_choice"] = toolChoiceJSONValue(request.toolChoice)
      }
    }

    if let openaiOptions = request.providerOptions?["openai"] {
      for (key, value) in openaiOptions { args[key] = value }
    }

    return args
  }

  private func mergeTextFormat(existing: JSONValue?, format: JSONValue) -> JSONValue {
    if case let .object(existingObject) = existing {
      var merged = existingObject
      merged["format"] = format
      return .object(merged)
    }
    return .object(["format": format])
  }

  private func mapTools(_ tools: [ToolDefinition]) -> JSONValue? {
    guard tools.isEmpty == false else { return nil }
    let strict = options.strictJsonSchema ?? false
    let mapped = tools.map { tool -> JSONValue in
      var function: [String: JSONValue] = [
        "type": .string("function"),
        "name": .string(tool.name),
        "parameters": .object(tool.inputSchema.value),
        "strict": .bool(strict),
      ]
      if let description = tool.description {
        function["description"] = .string(description)
      }
      return .object(function)
    }
    return .array(mapped)
  }

  private func toolChoiceJSONValue(_ toolChoice: ToolChoice) -> JSONValue? {
    switch toolChoice {
    case .auto:
      return .string("auto")
    case .none:
      return .string("none")
    case .required:
      return .string("required")
    case .tool(let name):
      return .object([
        "type": .string("function"),
        "name": .string(name),
      ])
    }
  }

  private func responseFormat(for format: ResponseFormat) -> JSONValue? {
    switch format {
    case .text:
      return nil
    case .json:
      return .object(["type": .string("json_object")])
    case .jsonSchema(let schema, let name, let description):
      var jsonSchema: [String: JSONValue] = [
        "type": .string("json_schema"),
        "schema": .object(schema.value),
        "strict": .bool(options.strictJsonSchema ?? true),
        "name": .string(name ?? "response"),
      ]
      if let description {
        jsonSchema["description"] = .string(description)
      }
      return .object(jsonSchema)
    }
  }

  private func mapUsage(from usage: OpenAIResponsesUsage?) -> Usage {
    if let usage {
      var input = Usage.InputTokens(total: usage.inputTokens)
      if let cached = usage.inputTokensDetails?.cachedTokens {
        input.cacheRead = cached
      }
      var output = Usage.OutputTokens(total: usage.outputTokens)
      if let reasoningTokens = usage.outputTokensDetails?.reasoningTokens {
        output.reasoning = reasoningTokens
      }
      return Usage(inputTokens: input, outputTokens: output)
    }
    return Usage(inputTokens: .init(), outputTokens: .init())
  }
}

private struct OpenAIResponsesFunctionCallBuffer {
  var callID: String
  var name: String
  var arguments: String
  var sent: Bool = false
}

func mapResponsesFinishReason(
  status: String?,
  incompleteReason: String?,
  hasToolCall: Bool
) -> FinishReason {
  switch status {
  case "completed":
    return hasToolCall ? .toolCalls : .stop
  case "incomplete":
    switch incompleteReason {
    case "max_output_tokens":
      return .length
    case "content_filter":
      return .contentFilter
    default:
      return .other
    }
  case "failed", "error":
    return .error
  default:
    return hasToolCall ? .toolCalls : .other
  }
}
