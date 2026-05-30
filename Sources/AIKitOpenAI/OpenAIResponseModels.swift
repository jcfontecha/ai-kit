import Foundation
import AIKitProviders

struct OpenAIUsage: Decodable {
  var promptTokens: Int
  var promptTokensDetails: OpenAIPromptTokensDetails?
  var completionTokens: Int
  var completionTokensDetails: OpenAICompletionTokensDetails?
  var totalTokens: Int

  enum CodingKeys: String, CodingKey {
    case promptTokens = "prompt_tokens"
    case promptTokensDetails = "prompt_tokens_details"
    case completionTokens = "completion_tokens"
    case completionTokensDetails = "completion_tokens_details"
    case totalTokens = "total_tokens"
  }
}

struct OpenAIPromptTokensDetails: Decodable {
  var cachedTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
  }
}

struct OpenAICompletionTokensDetails: Decodable {
  var reasoningTokens: Int?

  enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }
}
