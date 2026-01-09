import Foundation
import AIKitProviders

struct OpenRouterUsage: Decodable {
  var promptTokens: Int
  var promptTokensDetails: OpenRouterPromptTokensDetails?
  var completionTokens: Int
  var completionTokensDetails: OpenRouterCompletionTokensDetails?
  var totalTokens: Int
  var cost: Double?
  var costDetails: OpenRouterCostDetails?

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case promptTokensDetails = "prompt_tokens_details"
    case completionTokens = "completion_tokens"
    case completionTokensDetails = "completion_tokens_details"
    case totalTokens = "total_tokens"
    case cost
    case costDetails = "cost_details"
  }
}

struct OpenRouterPromptTokensDetails: Decodable {
  var cachedTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
  }
}

struct OpenRouterCompletionTokensDetails: Decodable {
  var reasoningTokens: Int?

  enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }
}

struct OpenRouterCostDetails: Decodable {
  var upstreamInferenceCost: Double?

  enum CodingKeys: String, CodingKey {
    case upstreamInferenceCost = "upstream_inference_cost"
  }
}

struct OpenRouterErrorPayload: Decodable {
  var code: JSONValue?
  var message: String
  var metadata: [String: JSONValue]?
  var type: String?
  var param: JSONValue?

  enum CodingKeys: String, CodingKey {
    case code
    case message
    case metadata
    case type
    case param
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    message = (try? container.decode(String.self, forKey: .message)) ?? ""
    code = try? container.decode(JSONValue.self, forKey: .code)
    metadata = try? container.decode([String: JSONValue].self, forKey: .metadata)
    type = try? container.decode(String.self, forKey: .type)
    param = try? container.decode(JSONValue.self, forKey: .param)
  }
}
