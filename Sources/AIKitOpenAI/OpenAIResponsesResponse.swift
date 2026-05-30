import Foundation

struct OpenAIResponsesEnvelope: Decodable {
  var id: String?
  var model: String?
  var status: String?
  var output: [OpenAIResponsesOutputItem]?
  var usage: OpenAIResponsesUsage?
  var incompleteDetails: OpenAIResponsesIncompleteDetails?
  var error: OpenAIErrorPayload?

  enum CodingKeys: String, CodingKey {
    case id, model, status, output, usage, error
    case incompleteDetails = "incomplete_details"
  }
}

struct OpenAIResponsesOutputItem: Decodable {
  var type: String
  var id: String?
  var callID: String?
  var name: String?
  var arguments: String?
  var content: [OpenAIResponsesContentPart]?
  var summary: [OpenAIResponsesSummaryPart]?

  enum CodingKeys: String, CodingKey {
    case type, id, name, arguments, content, summary
    case callID = "call_id"
  }
}

struct OpenAIResponsesContentPart: Decodable {
  var type: String
  var text: String?
}

struct OpenAIResponsesSummaryPart: Decodable {
  var type: String?
  var text: String?
}

struct OpenAIResponsesIncompleteDetails: Decodable {
  var reason: String?
}

struct OpenAIResponsesUsage: Decodable {
  var inputTokens: Int?
  var outputTokens: Int?
  var totalTokens: Int?
  var inputTokensDetails: OpenAIResponsesInputTokensDetails?
  var outputTokensDetails: OpenAIResponsesOutputTokensDetails?

  enum CodingKeys: String, CodingKey {
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case totalTokens = "total_tokens"
    case inputTokensDetails = "input_tokens_details"
    case outputTokensDetails = "output_tokens_details"
  }
}

struct OpenAIResponsesInputTokensDetails: Decodable {
  var cachedTokens: Int?

  enum CodingKeys: String, CodingKey {
    case cachedTokens = "cached_tokens"
  }
}

struct OpenAIResponsesOutputTokensDetails: Decodable {
  var reasoningTokens: Int?

  enum CodingKeys: String, CodingKey {
    case reasoningTokens = "reasoning_tokens"
  }
}

struct OpenAIResponsesStreamEvent: Decodable {
  var type: String
  var outputIndex: Int?
  var itemId: String?
  var delta: String?
  var arguments: String?
  var text: String?
  var message: String?
  var item: OpenAIResponsesOutputItem?
  var part: OpenAIResponsesContentPart?
  var response: OpenAIResponsesEnvelope?

  enum CodingKeys: String, CodingKey {
    case type, delta, arguments, text, message, item, part, response
    case outputIndex = "output_index"
    case itemId = "item_id"
  }
}
