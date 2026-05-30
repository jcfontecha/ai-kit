import Foundation
import AIKitProviders

struct OpenAIChatConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
}

struct OpenAIChatLanguageModel: LanguageModel, Sendable {
  let id: String
  let capabilities: ModelCapabilities = []
  let supportedURLs: SupportedURLPatterns = [
    "image/*": [
      URLPattern("^data:image/[a-zA-Z]+;base64,"),
      URLPattern("^https?://.+\\.(jpg|jpeg|png|gif|webp)$", options: .caseInsensitive),
    ],
    "application/*": [
      URLPattern("^data:application/"),
      URLPattern("^https?://.+$"),
    ],
  ]

  let modelId: OpenAIChatModelID
  let options: OpenAIChatLanguageModelOptions
  let config: OpenAIChatConfig

  init(modelId: OpenAIChatModelID, options: OpenAIChatLanguageModelOptions, config: OpenAIChatConfig) {
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

    var urlRequest = URLRequest(url: URL(string: config.url("/chat/completions"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)

    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: responseData)
    }

    let responseValue = try OpenAIJSON.decoder.decode(OpenAIChatCompletionResponseEnvelope.self, from: responseData)
    if let error = responseValue.error {
      throw OpenAIAPIError(message: error.message, statusCode: 200)
    }

    guard let responseChoices = responseValue.choices, let choice = responseChoices.first else {
      throw OpenAIInvalidResponseError(message: "No choice in response")
    }

    let usage = mapUsage(from: responseValue.usage)

    var content: [ModelContentPart] = []

    if let text = choice.message.content, text.isEmpty == false {
      content.append(.text(text))
    }

    if let toolCalls = choice.message.toolCalls {
      for toolCall in toolCalls {
        let toolID = toolCall.id ?? UUID().uuidString
        let inputJSON = toolCall.function.arguments
        let parsedInput = OpenAIJSON.isParsableJSON(inputJSON)
          ? (try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)))
          : nil
        content.append(
          .toolCall(
            ToolCall(
              toolCallID: toolID,
              toolName: toolCall.function.name,
              inputJSON: inputJSON,
              input: parsedInput,
              providerMetadata: nil
            )
          )
        )
      }
    }

    let finishReason = mapOpenAIFinishReason(choice.finishReason)
    let responseBody = try? OpenAIJSON.decoder.decode(JSONValue.self, from: responseData)

    return ModelResponse(
      content: content,
      finishReason: finishReason,
      rawFinishReason: choice.finishReason,
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
          args["stream_options"] = .object(["include_usage": .bool(true)])

          let bodyValue = JSONValue.object(args)
          let data = try OpenAIJSON.encodeToData(bodyValue)

          var urlRequest = URLRequest(url: URL(string: config.url("/chat/completions"))!)
          urlRequest.httpMethod = "POST"
          urlRequest.httpBody = data

          let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
          for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

          let (byteStream, response) = try await config.transport.bytes(for: urlRequest)

          guard response.statusCode == 200 else {
            throw await openAIAPIError(statusCode: response.statusCode, bytes: byteStream)
          }

          let sseStream = parseSSELines(byteStream)

          var toolCalls: [OpenAIToolCallBuffer] = []
          var finishReason: FinishReason = .other
          var usage = Usage(inputTokens: .init(), outputTokens: .init())

          var textStarted = false
          var textId: String?
          var openAIResponseId: String?

          for try await payload in sseStream {
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8) else { continue }
            let chunk: OpenAIChatCompletionStreamEnvelope
            do {
              chunk = try OpenAIJSON.decoder.decode(OpenAIChatCompletionStreamEnvelope.self, from: chunkData)
            } catch {
              finishReason = .error
              continuation.yield(.error(.init(message: error.localizedDescription)))
              break
            }

            if let error = chunk.error {
              finishReason = .error
              continuation.yield(
                .error(
                  ModelStreamError(
                    message: error.message,
                    type: error.type,
                    code: error.code,
                    param: error.param
                  )
                )
              )
              continue
            }

            if let id = chunk.id {
              openAIResponseId = id
              continuation.yield(.responseMetadata(.init(id: id)))
            }
            if let model = chunk.model {
              continuation.yield(.responseMetadata(.init(modelID: model)))
            }

            if let chunkUsage = chunk.usage {
              usage.inputTokens?.total = chunkUsage.promptTokens
              usage.outputTokens?.total = chunkUsage.completionTokens
              if let cached = chunkUsage.promptTokensDetails?.cachedTokens {
                usage.inputTokens?.cacheRead = cached
              }
              if let reasoningTokens = chunkUsage.completionTokensDetails?.reasoningTokens {
                usage.outputTokens?.reasoning = reasoningTokens
              }
            }

            let choice = chunk.choices?.first
            if let choice, let finish = choice.finishReason {
              finishReason = mapOpenAIFinishReason(finish)
            }

            guard let delta = choice?.delta else { continue }

            if let content = delta.content, content.isEmpty == false {
              if !textStarted {
                textId = openAIResponseId ?? UUID().uuidString
                continuation.yield(.textStart(id: textId ?? UUID().uuidString))
                textStarted = true
              }
              continuation.yield(.textDelta(id: textId ?? UUID().uuidString, text: content))
            }

            if let toolCallDeltas = delta.toolCalls {
              for toolCallDelta in toolCallDeltas {
                let index = toolCallDelta.index ?? (toolCalls.count - 1)
                if index < 0 { continue }
                if toolCalls.indices.contains(index) == false {
                  guard toolCallDelta.type == "function" else {
                    throw OpenAIInvalidResponseError(message: "Expected 'function' type.")
                  }
                  guard let id = toolCallDelta.id else {
                    throw OpenAIInvalidResponseError(message: "Expected 'id' to be a string.")
                  }
                  guard let name = toolCallDelta.function?.name else {
                    throw OpenAIInvalidResponseError(message: "Expected 'function.name' to be a string.")
                  }

                  let initialArguments = toolCallDelta.function?.arguments ?? ""
                  var buffer = OpenAIToolCallBuffer(
                    id: id,
                    name: name,
                    arguments: initialArguments,
                    inputStarted: false,
                    sent: false
                  )

                  if OpenAIJSON.isParsableJSON(buffer.arguments) {
                    buffer.inputStarted = true
                    continuation.yield(.toolInputStart(id: id, toolName: name))
                    continuation.yield(.toolInputDelta(id: id, delta: buffer.arguments))
                    continuation.yield(.toolInputEnd(id: id))
                    continuation.yield(
                      .toolCall(
                        ToolCall(
                          toolCallID: id,
                          toolName: name,
                          inputJSON: buffer.arguments,
                          input: try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(buffer.arguments.utf8)),
                          providerMetadata: nil
                        )
                      )
                    )
                    buffer.sent = true
                  }

                  toolCalls.append(buffer)
                  continue
                }

                guard var buffer = toolCalls[safe: index] else {
                  throw OpenAIInvalidResponseError(message: "Tool call at index \(index) is missing during merge.")
                }

                if buffer.inputStarted == false {
                  buffer.inputStarted = true
                  continuation.yield(.toolInputStart(id: buffer.id, toolName: buffer.name))
                }

                if let deltaArguments = toolCallDelta.function?.arguments {
                  buffer.arguments += deltaArguments
                  continuation.yield(.toolInputDelta(id: buffer.id, delta: deltaArguments))
                }

                if OpenAIJSON.isParsableJSON(buffer.arguments) {
                  continuation.yield(
                    .toolCall(
                      ToolCall(
                        toolCallID: buffer.id,
                        toolName: buffer.name,
                        inputJSON: buffer.arguments,
                        input: try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(buffer.arguments.utf8)),
                        providerMetadata: nil
                      )
                    )
                  )
                  buffer.sent = true
                }

                toolCalls[index] = buffer
              }
            }
          }

          if finishReason == .toolCalls {
            for (index, buffer) in toolCalls.enumerated() {
              if buffer.sent { continue }
              let inputJSON = OpenAIJSON.isParsableJSON(buffer.arguments) ? buffer.arguments : "{}"
              continuation.yield(
                .toolCall(
                  ToolCall(
                    toolCallID: buffer.id,
                    toolName: buffer.name,
                    inputJSON: inputJSON,
                    input: try? OpenAIJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)),
                    providerMetadata: nil
                  )
                )
              )
              toolCalls[index].sent = true
            }
          }

          if textStarted {
            continuation.yield(.textEnd(id: textId ?? UUID().uuidString))
          }

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
    let promptMessages = try convertToOpenAIChatMessages(
      request.messages,
      systemMessageMode: capabilities.systemMessageMode
    )
    var args: [String: JSONValue] = [
      "model": .string(modelId.rawValue),
      "messages": OpenAIJSON.encodeToJSONValue(promptMessages) ?? .array([]),
    ]

    if let logitBias = options.logitBias {
      var object: [String: JSONValue] = [:]
      for (key, value) in logitBias {
        object[key] = .number(value)
      }
      args["logit_bias"] = .object(object)
    }

    if let logprobs = options.logprobs {
      switch logprobs {
      case .enabled(let enabled):
        args["logprobs"] = .bool(enabled)
      case .topN(let count):
        args["logprobs"] = .bool(true)
        args["top_logprobs"] = .number(Double(count))
      }
    }

    if let parallel = options.parallelToolCalls {
      args["parallel_tool_calls"] = .bool(parallel)
    }
    if let user = options.user {
      args["user"] = .string(user)
    }
    if let reasoningEffort = options.reasoningEffort {
      args["reasoning_effort"] = .string(reasoningEffort.rawValue)
    }
    if let maxCompletionTokens = options.maxCompletionTokens {
      args["max_completion_tokens"] = .number(Double(maxCompletionTokens))
    }
    if let store = options.store {
      args["store"] = .bool(store)
    }
    if let metadata = options.metadata {
      args["metadata"] = .object(metadata.mapValues(JSONValue.string))
    }
    if let prediction = options.prediction {
      args["prediction"] = .object(prediction.mapValues(JSONValue.string))
    }
    if let serviceTier = options.serviceTier {
      args["service_tier"] = .string(serviceTier.rawValue)
    }
    if let promptCacheKey = options.promptCacheKey {
      args["prompt_cache_key"] = .string(promptCacheKey)
    }
    if let safetyIdentifier = options.safetyIdentifier {
      args["safety_identifier"] = .string(safetyIdentifier)
    }

    if let maxOutputTokens = request.settings.maxOutputTokens {
      args["max_tokens"] = .number(Double(maxOutputTokens))
    }
    if capabilities.supportsNonReasoningParameters || capabilities.isReasoningModel == false {
      if let temperature = request.settings.temperature {
        args["temperature"] = .number(temperature)
      }
      if let topP = request.settings.topP {
        args["top_p"] = .number(topP)
      }
    }
    if let frequencyPenalty = request.settings.frequencyPenalty {
      args["frequency_penalty"] = .number(frequencyPenalty)
    }
    if let presencePenalty = request.settings.presencePenalty {
      args["presence_penalty"] = .number(presencePenalty)
    }
    if let seed = request.settings.seed {
      args["seed"] = .number(Double(seed))
    }
    if let stopSequences = request.settings.stopSequences {
      args["stop"] = OpenAIJSON.encodeToJSONValue(stopSequences)
    }

    if let responseFormatValue = responseFormat(for: request.responseFormat) {
      args["response_format"] = responseFormatValue
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

  private func mapTools(_ tools: [ToolDefinition]) -> JSONValue? {
    guard tools.isEmpty == false else { return nil }
    let mapped = tools.map { tool in
      let parameters = openAICompatibleToolParametersSchema(tool.inputSchema.value)
      var function: [String: JSONValue] = [
        "name": .string(tool.name),
        "parameters": .object(parameters),
      ]
      if let description = tool.description {
        function["description"] = .string(description)
      }
      return JSONValue.object([
        "type": .string("function"),
        "function": .object(function),
      ])
    }
    return .array(mapped)
  }

  private func openAICompatibleToolParametersSchema(_ schema: [String: JSONValue]) -> [String: JSONValue] {
    guard case var .object(properties) = schema["properties"] else {
      return schema
    }

    let allKeys = Array(properties.keys).sorted()
    var requiredSet: Set<String> = []
    if case let .array(required)? = schema["required"] {
      for item in required {
        if case let .string(key) = item { requiredSet.insert(key) }
      }
    }

    for key in allKeys where requiredSet.contains(key) == false {
      guard case let .object(propertySchema) = properties[key] else { continue }
      properties[key] = .object([
        "anyOf": .array([
          .object(propertySchema),
          .object(["type": .string("null")]),
        ])
      ])
    }

    var updated = schema
    updated["properties"] = .object(properties)
    updated["required"] = .array(allKeys.map(JSONValue.string))
    return updated
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
        "function": .object(["name": .string(name)]),
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
        "schema": .object(schema.value),
        "strict": .bool(options.strictJsonSchema ?? true),
        "name": .string(name ?? "response"),
      ]
      if let description {
        jsonSchema["description"] = .string(description)
      }
      return .object([
        "type": .string("json_schema"),
        "json_schema": .object(jsonSchema),
      ])
    }
  }

  private func mapUsage(from usage: OpenAIUsage?) -> Usage {
    if let usage {
      var input = Usage.InputTokens(total: usage.promptTokens)
      if let cached = usage.promptTokensDetails?.cachedTokens {
        input.cacheRead = cached
      }
      var output = Usage.OutputTokens(total: usage.completionTokens)
      if let reasoningTokens = usage.completionTokensDetails?.reasoningTokens {
        output.reasoning = reasoningTokens
      }
      return Usage(inputTokens: input, outputTokens: output)
    }
    return Usage(inputTokens: .init(total: 0), outputTokens: .init(total: 0))
  }
}

private struct OpenAIToolCallBuffer {
  var id: String
  var name: String
  var arguments: String
  var inputStarted: Bool
  var sent: Bool
}

private struct OpenAIChatCompletionResponseEnvelope: Decodable {
  var id: String?
  var model: String?
  var usage: OpenAIUsage?
  var choices: [OpenAIChatCompletionChoice]?
  var error: OpenAIErrorPayload?
}

private struct OpenAIChatCompletionChoice: Decodable {
  var message: OpenAIChatCompletionMessage
  var finishReason: String?

  enum CodingKeys: String, CodingKey {
    case message
    case finishReason = "finish_reason"
  }
}

private struct OpenAIChatCompletionMessage: Decodable {
  var role: String?
  var content: String?
  var toolCalls: [OpenAIChatToolCallPayload]?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCalls = "tool_calls"
  }
}

private struct OpenAIChatToolCallPayload: Decodable {
  var id: String?
  var type: String
  var function: OpenAIChatToolCallFunction
}

private struct OpenAIChatCompletionStreamEnvelope: Decodable {
  var id: String?
  var model: String?
  var usage: OpenAIUsage?
  var choices: [OpenAIStreamChoice]?
  var error: OpenAIErrorPayload?
}

private struct OpenAIStreamChoice: Decodable {
  var delta: OpenAIStreamDelta?
  var finishReason: String?

  enum CodingKeys: String, CodingKey {
    case delta
    case finishReason = "finish_reason"
  }
}

private struct OpenAIStreamDelta: Decodable {
  var role: String?
  var content: String?
  var toolCalls: [OpenAIStreamToolCall]?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCalls = "tool_calls"
  }
}

private struct OpenAIStreamToolCall: Decodable {
  var index: Int?
  var id: String?
  var type: String?
  var function: OpenAIStreamToolCallFunction?
}

private struct OpenAIStreamToolCallFunction: Decodable {
  var name: String?
  var arguments: String?
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}
