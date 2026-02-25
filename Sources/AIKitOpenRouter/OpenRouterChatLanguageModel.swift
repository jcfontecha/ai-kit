import Foundation
import AIKitProviders

struct OpenRouterChatConfig: Sendable {
  var provider: String
  var compatibility: OpenRouterCompatibility
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
  var extraBody: [String: JSONValue]?
}

struct OpenRouterChatLanguageModel: LanguageModel, Sendable {
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

  let modelId: OpenRouterChatModelID
  let settings: OpenRouterChatSettings
  let config: OpenRouterChatConfig

  init(modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings, config: OpenRouterChatConfig) {
    self.modelId = modelId
    self.settings = settings
    self.config = config
    self.id = modelId
  }

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    let args = try buildArgs(from: request)
    let bodyValue = JSONValue.object(args)
    let data = try OpenRouterJSON.encodeToData(bodyValue)

    var urlRequest = URLRequest(url: URL(string: config.url("/chat/completions"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)

    guard response.statusCode == 200 else {
      throw openRouterAPIError(statusCode: response.statusCode, data: responseData)
    }

    let responseValue = try OpenRouterJSON.decoder.decode(OpenRouterChatCompletionResponseEnvelope.self, from: responseData)
    if let error = responseValue.error {
      throw OpenRouterAPIError(message: error.message, statusCode: 200)
    }

    guard let responseChoices = responseValue.choices, let choice = responseChoices.first else {
      throw OpenRouterInvalidResponseError(message: "No choice in response")
    }

    let usage = mapUsage(from: responseValue.usage)

    let reasoningDetails = choice.message.reasoningDetails ?? []
    let reasoningContent = buildReasoningContent(from: reasoningDetails, fallback: choice.message.reasoning)
    var content: [ModelContentPart] = []
    content.append(contentsOf: reasoningContent)

    if let text = choice.message.content, text.isEmpty == false {
      content.append(.text(text))
    }

    if let toolCalls = choice.message.toolCalls {
      for toolCall in toolCalls {
        let toolID = toolCall.id ?? UUID().uuidString
        let inputJSON = toolCall.function.arguments
        let parsedInput = OpenRouterJSON.isParsableJSON(inputJSON)
          ? (try? OpenRouterJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)))
          : nil
        let providerMetadata = openRouterProviderMetadata(
          reasoningDetails: reasoningDetails,
          annotations: nil,
          usage: nil,
          provider: nil,
          includeEmptyUsage: false,
          includeEmptyReasoningDetails: true
        )
        content.append(
          .toolCall(
            ToolCall(
              toolCallID: toolID,
              toolName: toolCall.function.name,
              inputJSON: inputJSON,
              input: parsedInput,
              providerMetadata: providerMetadata
            )
          )
        )
      }
    }

    if let images = choice.message.images {
      for image in images {
        let mediaType = getMediaType(from: image.imageURL.url, defaultMediaType: "image/jpeg")
        let base64 = getBase64FromDataUrl(image.imageURL.url)
        if let data = Data(base64Encoded: base64) {
          content.append(.file(.init(data: data, mediaType: mediaType)))
        }
      }
    }

    if let annotations = choice.message.annotations {
      for annotation in annotations {
        if case let .urlCitation(citation) = annotation {
          content.append(
            .source(
              .init(
                id: citation.urlCitation.url,
                url: citation.urlCitation.url,
                title: citation.urlCitation.title,
                providerMetadata: [
                  "openrouter": .object(["content": .string(citation.urlCitation.content ?? "")]),
                ]
              )
            )
          )
        }
      }
    }

    let fileAnnotations = choice.message.annotations?.compactMap { annotation -> OpenRouterFileAnnotation? in
      if case let .file(file) = annotation { return file }
      return nil
    }

    let hasToolCalls = (choice.message.toolCalls?.isEmpty == false)
    let hasEncryptedReasoning = reasoningDetails.contains { detail in
      if case let .encrypted(encrypted) = detail {
        return encrypted.data.isEmpty == false
      }
      return false
    }
    let shouldOverrideFinishReason = hasToolCalls && hasEncryptedReasoning && choice.finishReason == "stop"
    let finishReason = shouldOverrideFinishReason ? .toolCalls : mapOpenRouterFinishReason(choice.finishReason)

    let openRouterUsage = buildUsageAccounting(from: responseValue.usage, usage: usage)

    let providerMetadata = openRouterProviderMetadata(
      reasoningDetails: reasoningDetails,
      annotations: fileAnnotations,
      usage: openRouterUsage,
      provider: responseValue.provider
    )

    let responseBody = try? OpenRouterJSON.decoder.decode(JSONValue.self, from: responseData)

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
      providerMetadata: providerMetadata
    )
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      Task {
        do {
          var args = try buildArgs(from: request)
          args["stream"] = .bool(true)
          if config.compatibility == .strict {
            var streamOptions: [String: JSONValue] = ["include_usage": .bool(true)]
            if settings.usage?.include == true {
              streamOptions["include_usage"] = .bool(true)
            }
            args["stream_options"] = .object(streamOptions)
          }

          let bodyValue = JSONValue.object(args)
          let data = try OpenRouterJSON.encodeToData(bodyValue)

          var urlRequest = URLRequest(url: URL(string: config.url("/chat/completions"))!)
          urlRequest.httpMethod = "POST"
          urlRequest.httpBody = data

          let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
          for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

          let (byteStream, response) = try await config.transport.bytes(for: urlRequest)

          guard response.statusCode == 200 else {
            throw await openRouterAPIError(statusCode: response.statusCode, bytes: byteStream)
          }

          let sseStream = parseSSELines(byteStream)

          var toolCalls: [OpenRouterToolCallBuffer] = []
          var finishReason: FinishReason = .other
          var usage = Usage(
            inputTokens: .init(),
            outputTokens: .init()
          )
          var openRouterUsage: OpenRouterUsageAccounting?

          var accumulatedReasoningDetails: [ReasoningDetailUnion] = []
          var accumulatedFileAnnotations: [OpenRouterFileAnnotation] = []

          var textStarted = false
          var reasoningStarted = false
          var textId: String?
          var reasoningId: String?
          var openRouterResponseId: String?
          var provider: String?

          var shouldStopAfterError = false
          for try await payload in sseStream {
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8) else { continue }
            let chunk: OpenRouterChatCompletionStreamEnvelope
            do {
              chunk = try OpenRouterJSON.decoder.decode(OpenRouterChatCompletionStreamEnvelope.self, from: chunkData)
            } catch {
              finishReason = .error
              continuation.yield(.error(.init(message: error.localizedDescription)))
              shouldStopAfterError = true
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

            if let valueProvider = chunk.provider { provider = valueProvider }
            if let id = chunk.id {
              openRouterResponseId = id
              continuation.yield(.responseMetadata(.init(id: id)))
            }
            if let model = chunk.model {
              continuation.yield(.responseMetadata(.init(modelID: model)))
            }

            if let chunkUsage = chunk.usage {
              usage.inputTokens?.total = chunkUsage.promptTokens
              usage.outputTokens?.total = chunkUsage.completionTokens

              if openRouterUsage == nil {
                openRouterUsage = OpenRouterUsageAccounting(
                  promptTokens: chunkUsage.promptTokens,
                  completionTokens: chunkUsage.completionTokens,
                  totalTokens: chunkUsage.totalTokens,
                  cost: chunkUsage.cost
                )
              } else {
                openRouterUsage?.promptTokens = chunkUsage.promptTokens
                openRouterUsage?.completionTokens = chunkUsage.completionTokens
                openRouterUsage?.totalTokens = chunkUsage.totalTokens
                openRouterUsage?.cost = chunkUsage.cost
              }

              if let cached = chunkUsage.promptTokensDetails?.cachedTokens {
                usage.inputTokens?.cacheRead = cached
                openRouterUsage?.promptTokensDetails = .init(cachedTokens: cached)
              }
              if let reasoningTokens = chunkUsage.completionTokensDetails?.reasoningTokens {
                usage.outputTokens?.reasoning = reasoningTokens
                openRouterUsage?.completionTokensDetails = .init(reasoningTokens: reasoningTokens)
              }
              if let upstream = chunkUsage.costDetails?.upstreamInferenceCost {
                openRouterUsage?.costDetails = .init(upstreamInferenceCost: upstream)
              }
            }

            let choice = chunk.choices?.first
            if let choice, let finish = choice.finishReason {
              finishReason = mapOpenRouterFinishReason(finish)
            }

            guard let delta = choice?.delta else { continue }

            if let deltaReasoningDetails = delta.reasoningDetails, deltaReasoningDetails.isEmpty == false {
              for detail in deltaReasoningDetails {
                if case let .text(textDetail) = detail {
                  if let lastIndex = accumulatedReasoningDetails.indices.last,
                     case let .text(lastText) = accumulatedReasoningDetails[lastIndex] {
                    var updated = lastText
                    updated.text = (updated.text ?? "") + (textDetail.text ?? "")
                    if updated.signature == nil { updated.signature = textDetail.signature }
                    if updated.format == nil { updated.format = textDetail.format }
                    accumulatedReasoningDetails[lastIndex] = .text(updated)
                  } else {
                    accumulatedReasoningDetails.append(.text(textDetail))
                  }
                } else {
                  accumulatedReasoningDetails.append(detail)
                }
              }

              let reasoningMetadata = openRouterProviderMetadata(
                reasoningDetails: deltaReasoningDetails,
                annotations: nil,
                usage: nil,
                provider: nil,
                includeEmptyUsage: false
              )

              for detail in deltaReasoningDetails {
                switch detail {
                case .text(let textDetail):
                  if let text = textDetail.text {
                    emitReasoningChunk(
                      text: text,
                      responseId: openRouterResponseId,
                      reasoningStarted: &reasoningStarted,
                      reasoningId: &reasoningId,
                      continuation: continuation,
                      providerMetadata: reasoningMetadata
                    )
                  }
                case .encrypted(let encrypted):
                  if encrypted.data.isEmpty == false {
                    emitReasoningChunk(
                      text: "[REDACTED]",
                      responseId: openRouterResponseId,
                      reasoningStarted: &reasoningStarted,
                      reasoningId: &reasoningId,
                      continuation: continuation,
                      providerMetadata: reasoningMetadata
                    )
                  }
                case .summary(let summary):
                  emitReasoningChunk(
                    text: summary.summary,
                    responseId: openRouterResponseId,
                    reasoningStarted: &reasoningStarted,
                    reasoningId: &reasoningId,
                    continuation: continuation,
                    providerMetadata: reasoningMetadata
                  )
                }
              }
            } else if let reasoning = delta.reasoning {
              emitReasoningChunk(
                text: reasoning,
                responseId: openRouterResponseId,
                reasoningStarted: &reasoningStarted,
                reasoningId: &reasoningId,
                continuation: continuation,
                providerMetadata: nil
              )
            }

            if let content = delta.content, content.isEmpty == false {
              if reasoningStarted && !textStarted {
                continuation.yield(.reasoningEnd(id: reasoningId ?? UUID().uuidString))
                reasoningStarted = false
              }
              if !textStarted {
                textId = openRouterResponseId ?? UUID().uuidString
                continuation.yield(.textStart(id: textId ?? UUID().uuidString))
                textStarted = true
              }
              continuation.yield(.textDelta(id: textId ?? UUID().uuidString, text: content))
            }

            if let annotations = delta.annotations {
              for annotation in annotations {
                switch annotation {
                case .urlCitation(let citation):
                  continuation.yield(
                    .source(
                      .init(
                        id: citation.urlCitation.url,
                        url: citation.urlCitation.url,
                        title: citation.urlCitation.title,
                        providerMetadata: [
                          "openrouter": .object(["content": .string(citation.urlCitation.content ?? "")]),
                        ]
                      )
                    )
                  )
                case .file(let file):
                  accumulatedFileAnnotations.append(file)
                case .fileAnnotation:
                  break
                }
              }
            }

            if let toolCallDeltas = delta.toolCalls {
              for toolCallDelta in toolCallDeltas {
                let index = toolCallDelta.index ?? (toolCalls.count - 1)
                if index < 0 { continue }
                if toolCalls.indices.contains(index) == false {
                  guard toolCallDelta.type == "function" else {
                    throw OpenRouterInvalidResponseError(message: "Expected 'function' type.")
                  }
                  guard let id = toolCallDelta.id else {
                    throw OpenRouterInvalidResponseError(message: "Expected 'id' to be a string.")
                  }
                  guard let name = toolCallDelta.function?.name else {
                    throw OpenRouterInvalidResponseError(message: "Expected 'function.name' to be a string.")
                  }

                  let initialArguments = toolCallDelta.function?.arguments ?? ""
                  var buffer = OpenRouterToolCallBuffer(
                    id: id,
                    name: name,
                    arguments: initialArguments,
                    inputStarted: false,
                    sent: false
                  )

                  if OpenRouterJSON.isParsableJSON(buffer.arguments) {
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
                          input: try? OpenRouterJSON.decoder.decode(JSONValue.self, from: Data(buffer.arguments.utf8)),
                          providerMetadata: openRouterProviderMetadata(
                            reasoningDetails: accumulatedReasoningDetails,
                            annotations: nil,
                            usage: nil,
                            provider: nil,
                            includeEmptyUsage: false,
                            includeEmptyReasoningDetails: true
                          )
                        )
                      )
                    )
                    buffer.sent = true
                  }

                  toolCalls.append(buffer)
                  continue
                }

                guard var buffer = toolCalls[safe: index] else {
                  throw OpenRouterInvalidResponseError(message: "Tool call at index \(index) is missing during merge.")
                }

                if buffer.inputStarted == false {
                  buffer.inputStarted = true
                  continuation.yield(.toolInputStart(id: buffer.id, toolName: buffer.name))
                }

                if let deltaArguments = toolCallDelta.function?.arguments {
                  buffer.arguments += deltaArguments
                  continuation.yield(.toolInputDelta(id: buffer.id, delta: deltaArguments))
                }

                if OpenRouterJSON.isParsableJSON(buffer.arguments) {
                  continuation.yield(
                    .toolCall(
                      ToolCall(
                        toolCallID: buffer.id,
                        toolName: buffer.name,
                        inputJSON: buffer.arguments,
                        input: try? OpenRouterJSON.decoder.decode(JSONValue.self, from: Data(buffer.arguments.utf8)),
                        providerMetadata: openRouterProviderMetadata(
                          reasoningDetails: accumulatedReasoningDetails,
                          annotations: nil,
                          usage: nil,
                          provider: nil,
                          includeEmptyUsage: false,
                          includeEmptyReasoningDetails: true
                        )
                      )
                    )
                  )
                  buffer.sent = true
                }

                toolCalls[index] = buffer
              }
            }

            if let images = delta.images {
              for image in images {
                let mediaType = getMediaType(from: image.imageURL.url, defaultMediaType: "image/jpeg")
                let base64 = getBase64FromDataUrl(image.imageURL.url)
                if let data = Data(base64Encoded: base64) {
                  continuation.yield(.file(.init(data: data, mediaType: mediaType)))
                }
              }
            }
          }

          if shouldStopAfterError {
            // continue to finish emission below
          }

          let hasToolCalls = toolCalls.isEmpty == false
          let hasEncryptedReasoning = accumulatedReasoningDetails.contains { detail in
            if case let .encrypted(encrypted) = detail {
              return encrypted.data.isEmpty == false
            }
            return false
          }
          if hasToolCalls && hasEncryptedReasoning && finishReason == .stop {
            finishReason = .toolCalls
          }

          if finishReason == .toolCalls {
            for (index, buffer) in toolCalls.enumerated() {
              if buffer.sent { continue }
              let inputJSON = OpenRouterJSON.isParsableJSON(buffer.arguments) ? buffer.arguments : "{}"
              continuation.yield(
                .toolCall(
                  ToolCall(
                    toolCallID: buffer.id,
                    toolName: buffer.name,
                    inputJSON: inputJSON,
                    input: try? OpenRouterJSON.decoder.decode(JSONValue.self, from: Data(inputJSON.utf8)),
                    providerMetadata: openRouterProviderMetadata(
                      reasoningDetails: accumulatedReasoningDetails,
                      annotations: nil,
                      usage: nil,
                      provider: nil,
                      includeEmptyUsage: false,
                      includeEmptyReasoningDetails: true
                    )
                  )
                )
              )
              toolCalls[index].sent = true
            }
          }

          if reasoningStarted {
            continuation.yield(.reasoningEnd(id: reasoningId ?? UUID().uuidString))
          }
          if textStarted {
            continuation.yield(.textEnd(id: textId ?? UUID().uuidString))
          }

          let providerMetadata = openRouterProviderMetadata(
            reasoningDetails: accumulatedReasoningDetails.isEmpty ? nil : accumulatedReasoningDetails,
            annotations: accumulatedFileAnnotations.isEmpty ? nil : accumulatedFileAnnotations,
            usage: openRouterUsage,
            provider: provider,
            includeEmptyUsage: true
          )

          continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func buildArgs(from request: ModelRequest) throws -> [String: JSONValue] {
    let promptMessages = try convertToOpenRouterChatMessages(request.messages)
    var args: [String: JSONValue] = [
      "model": .string(modelId),
      "messages": OpenRouterJSON.encodeToJSONValue(promptMessages) ?? .array([])
    ]

    if let models = settings.models {
      args["models"] = OpenRouterJSON.encodeToJSONValue(models)
    }

    if let logitBias = settings.logitBias {
      var object: [String: JSONValue] = [:]
      for (key, value) in logitBias {
        object[String(key)] = .number(value)
      }
      args["logit_bias"] = .object(object)
    }

    if let logprobs = settings.logprobs {
      switch logprobs {
      case .enabled:
        args["logprobs"] = .bool(true)
        args["top_logprobs"] = .number(0)
      case .top(let count):
        args["logprobs"] = .bool(true)
        args["top_logprobs"] = .number(Double(count))
      case .disabled:
        break
      }
    }

    if let parallel = settings.parallelToolCalls {
      args["parallel_tool_calls"] = .bool(parallel)
    }

    if let user = settings.user {
      args["user"] = .string(user)
    }

    if let maxOutputTokens = request.settings.maxOutputTokens {
      args["max_tokens"] = .number(Double(maxOutputTokens))
    }
    if let temperature = request.settings.temperature {
      args["temperature"] = .number(temperature)
    }
    if let topP = request.settings.topP {
      args["top_p"] = .number(topP)
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
      args["stop"] = OpenRouterJSON.encodeToJSONValue(stopSequences)
    }
    if let topK = request.settings.topK {
      args["top_k"] = .number(Double(topK))
    }

    if let responseFormatValue = responseFormat(for: request.responseFormat) {
      args["response_format"] = responseFormatValue
    }

    if let includeReasoning = settings.includeReasoning {
      args["include_reasoning"] = .bool(includeReasoning)
    }
    if let reasoning = settings.reasoning {
      args["reasoning"] = reasoningJSONValue(reasoning)
    }
    if let usage = settings.usage {
      args["usage"] = .object(["include": .bool(usage.include)])
    }
    if let plugins = settings.plugins {
      args["plugins"] = OpenRouterJSON.encodeToJSONValue(plugins)
    }
    if let webSearchOptions = settings.webSearchOptions {
      args["web_search_options"] = webSearchOptionsJSONValue(webSearchOptions)
    }
    if let provider = settings.provider {
      args["provider"] = providerJSONValue(provider)
    }
    if let debug = settings.debug {
      args["debug"] = debugJSONValue(debug)
    }

    if let extra = config.extraBody {
      for (key, value) in extra { args[key] = value }
    }
    if let extra = settings.extraBody {
      for (key, value) in extra { args[key] = value }
    }

    if let tools = mapTools(request.tools) {
      args["tools"] = tools
      if request.toolChoice != .auto {
        args["tool_choice"] = toolChoiceJSONValue(request.toolChoice)
      }
    }

    if let openrouterOptions = request.providerOptions?["openrouter"] {
      for (key, value) in openrouterOptions { args[key] = value }
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
    case .json(let name, let description):
      if name != nil || description != nil {
        return .object(["type": .string("json_object")])
      }
      return .object(["type": .string("json_object")])
    case .jsonSchema(let schema, let name, let description):
      var jsonSchema: [String: JSONValue] = [
        "schema": .object(schema.value),
        "strict": .bool(true),
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

  private func reasoningJSONValue(_ reasoning: OpenRouterReasoning) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let enabled = reasoning.enabled { object["enabled"] = .bool(enabled) }
    if let exclude = reasoning.exclude { object["exclude"] = .bool(exclude) }
    if let maxTokens = reasoning.maxTokens { object["max_tokens"] = .number(Double(maxTokens)) }
    if let effort = reasoning.effort { object["effort"] = .string(effort.rawValue) }
    return .object(object)
  }

  private func webSearchOptionsJSONValue(_ options: OpenRouterWebSearchOptions) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let maxResults = options.maxResults { object["max_results"] = .number(Double(maxResults)) }
    if let searchPrompt = options.searchPrompt { object["search_prompt"] = .string(searchPrompt) }
    if let engine = options.engine { object["engine"] = .string(engine) }
    return .object(object)
  }

  private func providerJSONValue(_ provider: OpenRouterProviderRouting) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let order = provider.order { object["order"] = OpenRouterJSON.encodeToJSONValue(order) ?? .array([]) }
    if let allowFallbacks = provider.allowFallbacks { object["allow_fallbacks"] = .bool(allowFallbacks) }
    if let requireParameters = provider.requireParameters { object["require_parameters"] = .bool(requireParameters) }
    if let dataCollection = provider.dataCollection { object["data_collection"] = .string(dataCollection) }
    if let only = provider.only { object["only"] = OpenRouterJSON.encodeToJSONValue(only) ?? .array([]) }
    if let ignore = provider.ignore { object["ignore"] = OpenRouterJSON.encodeToJSONValue(ignore) ?? .array([]) }
    if let quantizations = provider.quantizations { object["quantizations"] = OpenRouterJSON.encodeToJSONValue(quantizations) ?? .array([]) }
    if let sort = provider.sort { object["sort"] = .string(sort) }
    if let maxPrice = provider.maxPrice { object["max_price"] = maxPriceJSONValue(maxPrice) }
    if let zdr = provider.zdr { object["zdr"] = .bool(zdr) }
    return .object(object)
  }

  private func maxPriceJSONValue(_ price: OpenRouterMaxPrice) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let prompt = price.prompt { object["prompt"] = prompt }
    if let completion = price.completion { object["completion"] = completion }
    if let image = price.image { object["image"] = image }
    if let audio = price.audio { object["audio"] = audio }
    if let request = price.request { object["request"] = request }
    return .object(object)
  }

  private func debugJSONValue(_ debug: OpenRouterDebugOptions) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let echo = debug.echoUpstreamBody { object["echo_upstream_body"] = .bool(echo) }
    return .object(object)
  }

  private func mapUsage(from usage: OpenRouterUsage?) -> Usage {
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

  private func buildUsageAccounting(from usage: OpenRouterUsage?, usage mappedUsage: Usage) -> OpenRouterUsageAccounting {
    let prompt = usage?.promptTokens ?? (mappedUsage.inputTokens?.total ?? 0)
    let completion = usage?.completionTokens ?? (mappedUsage.outputTokens?.total ?? 0)
    let total = usage?.totalTokens ?? (prompt + completion)
    var result = OpenRouterUsageAccounting(
      promptTokens: prompt,
      completionTokens: completion,
      totalTokens: total,
      cost: usage?.cost
    )

    if let cached = usage?.promptTokensDetails?.cachedTokens {
      result.promptTokensDetails = .init(cachedTokens: cached)
    }
    if let reasoning = usage?.completionTokensDetails?.reasoningTokens {
      result.completionTokensDetails = .init(reasoningTokens: reasoning)
    }
    if let upstream = usage?.costDetails?.upstreamInferenceCost {
      result.costDetails = .init(upstreamInferenceCost: upstream)
    }
    return result
  }

  private func openRouterProviderMetadata(
    reasoningDetails: [ReasoningDetailUnion]?,
    annotations: [OpenRouterFileAnnotation]?,
    usage: OpenRouterUsageAccounting?,
    provider: String?,
    includeEmptyUsage: Bool = false,
    includeEmptyReasoningDetails: Bool = false
  ) -> ProviderMetadata? {
    var payload: [String: JSONValue] = [:]
    if let provider {
      payload["provider"] = .string(provider)
    }
    if let reasoningDetails, let json = OpenRouterJSON.encodeToJSONValue(reasoningDetails) {
      if includeEmptyReasoningDetails || reasoningDetails.isEmpty == false {
        payload["reasoning_details"] = json
      }
    }
    if let annotations, annotations.isEmpty == false,
       let json = OpenRouterJSON.encodeToJSONValue(annotations) {
      payload["annotations"] = json
    }
    if let usage, let json = OpenRouterJSON.encodeToJSONValue(usage) {
      payload["usage"] = json
    } else if includeEmptyUsage {
      payload["usage"] = .object([:])
    }
    return payload.isEmpty ? nil : ["openrouter": .object(payload)]
  }

  private func buildReasoningContent(
    from details: [ReasoningDetailUnion],
    fallback: String?
  ) -> [ModelContentPart] {
    guard details.isEmpty == false else {
      if let fallback { return [.reasoning(fallback)] }
      return []
    }
    var parts: [ModelContentPart] = []
    for detail in details {
      switch detail {
      case .text(let text):
        if let textValue = text.text {
          parts.append(
            ModelContentPart.reasoning(
              textValue,
              metadata: openRouterProviderMetadata(
                reasoningDetails: [detail],
                annotations: nil,
                usage: nil,
                provider: nil,
                includeEmptyUsage: false
              )
            )
          )
        }
      case .summary(let summary):
        parts.append(
          ModelContentPart.reasoning(
            summary.summary,
            metadata: openRouterProviderMetadata(
              reasoningDetails: [detail],
              annotations: nil,
              usage: nil,
              provider: nil,
              includeEmptyUsage: false
            )
          )
        )
      case .encrypted(let encrypted):
        if encrypted.data.isEmpty == false {
          parts.append(
            ModelContentPart.reasoning(
              "[REDACTED]",
              metadata: openRouterProviderMetadata(
                reasoningDetails: [detail],
                annotations: nil,
                usage: nil,
                provider: nil,
                includeEmptyUsage: false
              )
            )
          )
        }
      }
    }
    return parts
  }
}

private func emitReasoningChunk(
  text: String,
  responseId: String?,
  reasoningStarted: inout Bool,
  reasoningId: inout String?,
  continuation: AsyncThrowingStream<ModelStreamPart, Error>.Continuation,
  providerMetadata: ProviderMetadata?
) {
  if reasoningStarted == false {
    reasoningId = responseId ?? UUID().uuidString
    continuation.yield(.reasoningStart(id: reasoningId ?? UUID().uuidString, providerMetadata: providerMetadata))
    reasoningStarted = true
  }
  continuation.yield(.reasoningDelta(id: reasoningId ?? UUID().uuidString, text: text, providerMetadata: providerMetadata))
}

private struct OpenRouterToolCallBuffer {
  var id: String
  var name: String
  var arguments: String
  var inputStarted: Bool
  var sent: Bool
}

private struct OpenRouterChatCompletionResponseEnvelope: Decodable {
  var id: String?
  var model: String?
  var provider: String?
  var usage: OpenRouterUsage?
  var choices: [OpenRouterChatCompletionChoice]?
  var error: OpenRouterErrorPayload?
}

private struct OpenRouterChatCompletionChoice: Decodable {
  var message: OpenRouterChatCompletionMessage
  var finishReason: String?

  enum CodingKeys: String, CodingKey {
    case message
    case finishReason = "finish_reason"
  }
}

private struct OpenRouterChatCompletionMessage: Decodable {
  var role: String?
  var content: String?
  var reasoning: String?
  var reasoningDetails: [ReasoningDetailUnion]?
  var images: [OpenRouterImageResponse]?
  var toolCalls: [OpenRouterChatToolCallPayload]?
  var annotations: [OpenRouterAnnotation]?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case reasoning
    case reasoningDetails = "reasoning_details"
    case images
    case toolCalls = "tool_calls"
    case annotations
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    content = try container.decodeIfPresent(String.self, forKey: .content)
    reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
    if let details = try container.decodeIfPresent(LossyDecodingArray<ReasoningDetailUnion>.self, forKey: .reasoningDetails) {
      reasoningDetails = details.elements
    } else {
      reasoningDetails = nil
    }
    if let images = try container.decodeIfPresent(LossyDecodingArray<OpenRouterImageResponse>.self, forKey: .images) {
      self.images = images.elements
    } else {
      self.images = nil
    }
    toolCalls = try container.decodeIfPresent([OpenRouterChatToolCallPayload].self, forKey: .toolCalls)
    if let annotations = try container.decodeIfPresent(LossyDecodingArray<OpenRouterAnnotation>.self, forKey: .annotations) {
      self.annotations = annotations.elements
    } else {
      self.annotations = nil
    }
  }
}

private struct OpenRouterChatToolCallPayload: Decodable {
  var id: String?
  var type: String
  var function: OpenRouterChatToolCallFunction
}

private struct OpenRouterChatCompletionStreamEnvelope: Decodable {
  var id: String?
  var model: String?
  var provider: String?
  var usage: OpenRouterUsage?
  var choices: [OpenRouterStreamChoice]?
  var error: OpenRouterErrorPayload?
}

private struct OpenRouterStreamChoice: Decodable {
  var delta: OpenRouterStreamDelta?
  var finishReason: String?

  enum CodingKeys: String, CodingKey {
    case delta
    case finishReason = "finish_reason"
  }
}

private struct OpenRouterStreamDelta: Decodable {
  var role: String?
  var content: String?
  var reasoning: String?
  var reasoningDetails: [ReasoningDetailUnion]?
  var images: [OpenRouterImageResponse]?
  var toolCalls: [OpenRouterStreamToolCall]?
  var annotations: [OpenRouterAnnotation]?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case reasoning
    case reasoningDetails = "reasoning_details"
    case images
    case toolCalls = "tool_calls"
    case annotations
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    role = try container.decodeIfPresent(String.self, forKey: .role)
    content = try container.decodeIfPresent(String.self, forKey: .content)
    reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
    if let details = try container.decodeIfPresent(LossyDecodingArray<ReasoningDetailUnion>.self, forKey: .reasoningDetails) {
      reasoningDetails = details.elements
    } else {
      reasoningDetails = nil
    }
    if let images = try container.decodeIfPresent(LossyDecodingArray<OpenRouterImageResponse>.self, forKey: .images) {
      self.images = images.elements
    } else {
      self.images = nil
    }
    toolCalls = try container.decodeIfPresent([OpenRouterStreamToolCall].self, forKey: .toolCalls)
    if let annotations = try container.decodeIfPresent(LossyDecodingArray<OpenRouterAnnotation>.self, forKey: .annotations) {
      self.annotations = annotations.elements
    } else {
      self.annotations = nil
    }
  }
}

private struct OpenRouterStreamToolCall: Decodable {
  var index: Int?
  var id: String?
  var type: String?
  var function: OpenRouterStreamToolCallFunction?
}

private struct OpenRouterStreamToolCallFunction: Decodable {
  var name: String?
  var arguments: String?
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}
