import Foundation
import AIKitProviders

struct OpenRouterEmbeddingConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
  var extraBody: [String: JSONValue]?
}

struct OpenRouterEmbeddingModel: EmbeddingModel, Sendable {
  let id: String
  let modelId: OpenRouterEmbeddingModelID
  let settings: OpenRouterEmbeddingSettings
  let config: OpenRouterEmbeddingConfig

  init(modelId: OpenRouterEmbeddingModelID, settings: OpenRouterEmbeddingSettings, config: OpenRouterEmbeddingConfig) {
    self.modelId = modelId
    self.settings = settings
    self.config = config
    self.id = modelId
  }

  func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
    var args: [String: JSONValue] = [
      "model": .string(modelId),
      "input": OpenRouterJSON.encodeToJSONValue(request.input) ?? .array([]),
    ]
    if let user = settings.user {
      args["user"] = .string(user)
    }
    if let provider = settings.provider {
      args["provider"] = providerJSONValue(provider)
    }
    if let extra = config.extraBody {
      for (key, value) in extra { args[key] = value }
    }
    if let extra = settings.extraBody {
      for (key, value) in extra { args[key] = value }
    }

    let bodyValue = JSONValue.object(args)
    let data = try OpenRouterJSON.encodeToData(bodyValue)

    var urlRequest = URLRequest(url: URL(string: config.url("/embeddings"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw openRouterAPIError(statusCode: response.statusCode, data: responseData)
    }

    let responseValue = try OpenRouterJSON.decoder.decode(OpenRouterEmbeddingResponse.self, from: responseData)
    let vectors = responseValue.data.map { $0.embedding }
    let usage = responseValue.usage.map { Usage(inputTokens: .init(total: $0.promptTokens), outputTokens: nil) }

    var providerMetadata: ProviderMetadata?
    if let cost = responseValue.usage?.cost {
      providerMetadata = [
        "openrouter": .object([
          "usage": .object(["cost": .number(cost)]),
        ]),
      ]
    }

    return EmbeddingResponse(
      vectors: vectors,
      modelID: responseValue.model,
      usage: usage,
      providerMetadata: providerMetadata
    )
  }

  private func providerJSONValue(_ provider: OpenRouterEmbeddingProviderRouting) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let order = provider.order { object["order"] = OpenRouterJSON.encodeToJSONValue(order) ?? .array([]) }
    if let allowFallbacks = provider.allowFallbacks { object["allow_fallbacks"] = .bool(allowFallbacks) }
    if let requireParameters = provider.requireParameters { object["require_parameters"] = .bool(requireParameters) }
    if let dataCollection = provider.dataCollection { object["data_collection"] = .string(dataCollection) }
    if let only = provider.only { object["only"] = OpenRouterJSON.encodeToJSONValue(only) ?? .array([]) }
    if let ignore = provider.ignore { object["ignore"] = OpenRouterJSON.encodeToJSONValue(ignore) ?? .array([]) }
    if let sort = provider.sort { object["sort"] = .string(sort) }
    if let maxPrice = provider.maxPrice { object["max_price"] = maxPriceJSONValue(maxPrice) }
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
}

private struct OpenRouterEmbeddingResponse: Decodable {
  var id: String?
  var object: String
  var data: [OpenRouterEmbeddingData]
  var model: String
  var usage: OpenRouterEmbeddingUsage?
}

private struct OpenRouterEmbeddingData: Decodable {
  var object: String
  var embedding: [Double]
  var index: Int?
}

private struct OpenRouterEmbeddingUsage: Decodable {
  var promptTokens: Int
  var totalTokens: Int
  var cost: Double?

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case totalTokens = "total_tokens"
    case cost
  }
}
