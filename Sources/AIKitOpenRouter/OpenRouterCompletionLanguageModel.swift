import Foundation
import AIKitProviders

struct OpenRouterCompletionConfig: Sendable {
  var provider: String
  var compatibility: OpenRouterCompatibility
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
  var extraBody: [String: JSONValue]?
}

public struct OpenRouterCompletionLanguageModel: LanguageModel, Sendable {
  public let id: String
  public let capabilities: ModelCapabilities = []
  public let supportedURLs: SupportedURLPatterns = [
    "image/*": [
      URLPattern("^data:image/[a-zA-Z]+;base64,"),
      URLPattern("^https?://.+\\.(jpg|jpeg|png|gif|webp)$", options: .caseInsensitive),
    ],
    "text/*": [
      URLPattern("^data:text/"),
      URLPattern("^https?://.+$"),
    ],
    "application/*": [
      URLPattern("^data:application/"),
      URLPattern("^https?://.+$"),
    ],
  ]

  let modelId: OpenRouterCompletionModelID
  let settings: OpenRouterCompletionSettings
  let config: OpenRouterCompletionConfig

  init(modelId: OpenRouterCompletionModelID, settings: OpenRouterCompletionSettings, config: OpenRouterCompletionConfig) {
    self.modelId = modelId
    self.settings = settings
    self.config = config
    self.id = modelId
  }

  public func generate(_ request: ModelRequest) async throws -> ModelResponse {
    let args = try buildArgs(from: request)
    let bodyValue = JSONValue.object(args)
    let data = try OpenRouterJSON.encodeToData(bodyValue)

    var urlRequest = URLRequest(url: URL(string: config.url("/completions"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw OpenRouterAPIError(message: "OpenRouter API error: \(response.statusCode)", statusCode: response.statusCode)
    }

    let responseValue = try OpenRouterJSON.decoder.decode(OpenRouterCompletionResponseEnvelope.self, from: responseData)
    if let error = responseValue.error {
      throw OpenRouterAPIError(message: error.message, statusCode: 200)
    }

    guard let choice = responseValue.choices?.first else {
      throw OpenRouterInvalidResponseError(message: "No choice in OpenRouter completion response")
    }

    let usage = mapUsage(from: responseValue.usage)
    let content: [ModelContentPart] = [.text(choice.text ?? "")]
    let finishReason = mapOpenRouterFinishReason(choice.finishReason)

    let openRouterUsage = buildUsageAccounting(from: responseValue.usage, usage: usage)
    let providerMetadata = openRouterProviderMetadata(usage: openRouterUsage)

    let responseBody = try? OpenRouterJSON.decoder.decode(JSONValue.self, from: responseData)

    return ModelResponse(
      content: content,
      finishReason: finishReason,
      rawFinishReason: choice.finishReason,
      usage: usage,
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

  public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      Task {
        do {
          var args = try buildArgs(from: request)
          args["stream"] = .bool(true)
          if config.compatibility == .strict {
            args["stream_options"] = .object(["include_usage": .bool(true)])
          }

          let bodyValue = JSONValue.object(args)
          let data = try OpenRouterJSON.encodeToData(bodyValue)

          var urlRequest = URLRequest(url: URL(string: config.url("/completions"))!)
          urlRequest.httpMethod = "POST"
          urlRequest.httpBody = data

          let headers = combineHeaders([config.headers(), request.headers, ["Content-Type": "application/json"]])
          for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

          let (byteStream, response) = try await config.transport.bytes(for: urlRequest)
          guard response.statusCode == 200 else {
            throw OpenRouterAPIError(message: "OpenRouter API error: \(response.statusCode)", statusCode: response.statusCode)
          }

          let sseStream = parseSSELines(byteStream)
          var finishReason: FinishReason = .other
          var usage = Usage(inputTokens: .init(), outputTokens: .init())
          var openRouterUsage: OpenRouterUsageAccounting?

          for try await payload in sseStream {
            if payload == "[DONE]" { break }
            guard let chunkData = payload.data(using: .utf8) else { continue }
            let chunk: OpenRouterCompletionResponseEnvelope
            do {
              chunk = try OpenRouterJSON.decoder.decode(OpenRouterCompletionResponseEnvelope.self, from: chunkData)
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

            if let choice = chunk.choices?.first {
              if let finish = choice.finishReason {
                finishReason = mapOpenRouterFinishReason(finish)
              }
              if let text = choice.text {
                continuation.yield(.textDelta(id: UUID().uuidString, text: text))
              }
            }
          }

          let providerMetadata = openRouterProviderMetadata(usage: openRouterUsage, includeEmptyUsage: true)
          continuation.yield(.finish(finishReason: finishReason, usage: usage, providerMetadata: providerMetadata))
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
    }
  }

  private func buildArgs(from request: ModelRequest) throws -> [String: JSONValue] {
    if request.tools.isEmpty == false {
      throw OpenRouterUnsupportedFunctionalityError(functionality: "tools")
    }
    if request.toolChoice != .auto {
      throw OpenRouterUnsupportedFunctionalityError(functionality: "toolChoice")
    }

    let prompt = try convertToOpenRouterCompletionPrompt(messages: request.messages)

    var args: [String: JSONValue] = [
      "model": .string(modelId),
      "prompt": .string(prompt),
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
        args["logprobs"] = .number(0)
      case .top(let count):
        args["logprobs"] = .number(Double(count))
      case .disabled:
        break
      }
    }

    if let suffix = settings.suffix {
      args["suffix"] = .string(suffix)
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

    if let extra = config.extraBody {
      for (key, value) in extra { args[key] = value }
    }
    if let extra = settings.extraBody {
      for (key, value) in extra { args[key] = value }
    }
    if let openrouterOptions = request.providerOptions?["openrouter"] {
      for (key, value) in openrouterOptions { args[key] = value }
    }

    return args
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
    usage: OpenRouterUsageAccounting?,
    includeEmptyUsage: Bool = false
  ) -> ProviderMetadata? {
    var payload: [String: JSONValue] = [:]
    if let usage, let json = OpenRouterJSON.encodeToJSONValue(usage) {
      payload["usage"] = json
    } else if includeEmptyUsage {
      payload["usage"] = .object([:])
    }
    return payload.isEmpty ? nil : ["openrouter": .object(payload)]
  }
}

private struct OpenRouterCompletionResponseEnvelope: Decodable {
  var id: String?
  var model: String?
  var choices: [OpenRouterCompletionChoice]?
  var usage: OpenRouterUsage?
  var error: OpenRouterErrorPayload?
}

private struct OpenRouterCompletionChoice: Decodable {
  var text: String?
  var finishReason: String?

  enum CodingKeys: String, CodingKey {
    case text
    case finishReason = "finish_reason"
  }
}
