import Foundation
import AIKitProviders

public struct OpenAIEmbeddingSettings: Sendable, Equatable {
  public var dimensions: Int?
  public var encodingFormat: String?
  public var user: String?

  public init(
    dimensions: Int? = nil,
    encodingFormat: String? = nil,
    user: String? = nil
  ) {
    self.dimensions = dimensions
    self.encodingFormat = encodingFormat
    self.user = user
  }
}

struct OpenAIEmbeddingConfig: Sendable {
  var provider: String
  var headers: @Sendable () -> [String: String]
  var url: @Sendable (String) -> String
  var transport: HTTPTransport
}

struct OpenAIEmbeddingModel: EmbeddingModel, Sendable {
  let id: String
  let modelId: OpenAIEmbeddingModelID
  let settings: OpenAIEmbeddingSettings
  let config: OpenAIEmbeddingConfig

  init(modelId: OpenAIEmbeddingModelID, settings: OpenAIEmbeddingSettings, config: OpenAIEmbeddingConfig) {
    self.modelId = modelId
    self.settings = settings
    self.config = config
    self.id = modelId.rawValue
  }

  func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
    var args: [String: JSONValue] = [
      "model": .string(modelId.rawValue),
      "input": OpenAIJSON.encodeToJSONValue(request.input) ?? .array([]),
    ]
    if let dimensions = settings.dimensions {
      args["dimensions"] = .number(Double(dimensions))
    }
    if let encodingFormat = settings.encodingFormat {
      args["encoding_format"] = .string(encodingFormat)
    }
    if let user = settings.user {
      args["user"] = .string(user)
    }

    let bodyValue = JSONValue.object(args)
    let data = try OpenAIJSON.encodeToData(bodyValue)

    var urlRequest = URLRequest(url: URL(string: config.url("/embeddings"))!)
    urlRequest.httpMethod = "POST"
    urlRequest.httpBody = data

    let headers = combineHeaders([config.headers(), ["Content-Type": "application/json"]])
    for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }

    let (responseData, response) = try await config.transport.data(for: urlRequest)
    guard response.statusCode == 200 else {
      throw openAIAPIError(statusCode: response.statusCode, data: responseData)
    }

    let responseValue = try OpenAIJSON.decoder.decode(OpenAIEmbeddingResponse.self, from: responseData)
    let vectors = responseValue.data.map { $0.embedding }
    let usage = responseValue.usage.map { Usage(inputTokens: .init(total: $0.promptTokens), outputTokens: nil) }

    return EmbeddingResponse(
      vectors: vectors,
      modelID: responseValue.model,
      usage: usage,
      providerMetadata: nil
    )
  }
}

private struct OpenAIEmbeddingResponse: Decodable {
  var object: String?
  var data: [OpenAIEmbeddingData]
  var model: String
  var usage: OpenAIEmbeddingUsage?
}

private struct OpenAIEmbeddingData: Decodable {
  var object: String?
  var embedding: [Double]
  var index: Int?
}

private struct OpenAIEmbeddingUsage: Decodable {
  var promptTokens: Int
  var totalTokens: Int

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case totalTokens = "total_tokens"
  }
}
