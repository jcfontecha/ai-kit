import Foundation
import AIKitProviders

public typealias OpenRouterChatModelID = String
public typealias OpenRouterCompletionModelID = String
public typealias OpenRouterEmbeddingModelID = String

public struct OpenRouterUsageAccounting: Sendable, Codable, Equatable {
  public var promptTokens: Int
  public var promptTokensDetails: PromptTokensDetails?
  public var completionTokens: Int
  public var completionTokensDetails: CompletionTokensDetails?
  public var totalTokens: Int
  public var cost: Double?
  public var costDetails: CostDetails?

  public struct PromptTokensDetails: Sendable, Codable, Equatable {
    public var cachedTokens: Int
    public init(cachedTokens: Int) {
      self.cachedTokens = cachedTokens
    }
  }

  public struct CompletionTokensDetails: Sendable, Codable, Equatable {
    public var reasoningTokens: Int
    public init(reasoningTokens: Int) {
      self.reasoningTokens = reasoningTokens
    }
  }

  public struct CostDetails: Sendable, Codable, Equatable {
    public var upstreamInferenceCost: Double
    public init(upstreamInferenceCost: Double) {
      self.upstreamInferenceCost = upstreamInferenceCost
    }
  }

  public init(
    promptTokens: Int,
    promptTokensDetails: PromptTokensDetails? = nil,
    completionTokens: Int,
    completionTokensDetails: CompletionTokensDetails? = nil,
    totalTokens: Int,
    cost: Double? = nil,
    costDetails: CostDetails? = nil
  ) {
    self.promptTokens = promptTokens
    self.promptTokensDetails = promptTokensDetails
    self.completionTokens = completionTokens
    self.completionTokensDetails = completionTokensDetails
    self.totalTokens = totalTokens
    self.cost = cost
    self.costDetails = costDetails
  }
}

public struct OpenRouterSharedSettings: Sendable, Equatable {
  public var models: [String]?
  public var reasoning: OpenRouterReasoning?
  public var user: String?
  public var includeReasoning: Bool?
  public var extraBody: [String: JSONValue]?
  public var usage: OpenRouterUsageOption?

  public init(
    models: [String]? = nil,
    reasoning: OpenRouterReasoning? = nil,
    user: String? = nil,
    includeReasoning: Bool? = nil,
    extraBody: [String: JSONValue]? = nil,
    usage: OpenRouterUsageOption? = nil
  ) {
    self.models = models
    self.reasoning = reasoning
    self.user = user
    self.includeReasoning = includeReasoning
    self.extraBody = extraBody
    self.usage = usage
  }
}

public struct OpenRouterReasoning: Sendable, Equatable {
  public var enabled: Bool?
  public var exclude: Bool?
  public var maxTokens: Int?
  public var effort: OpenRouterReasoningEffort?

  public init(
    enabled: Bool? = nil,
    exclude: Bool? = nil,
    maxTokens: Int? = nil,
    effort: OpenRouterReasoningEffort? = nil
  ) {
    self.enabled = enabled
    self.exclude = exclude
    self.maxTokens = maxTokens
    self.effort = effort
  }
}

public enum OpenRouterReasoningEffort: String, Sendable, Codable {
  case high
  case medium
  case low
}

public struct OpenRouterUsageOption: Sendable, Equatable {
  public var include: Bool
  public init(include: Bool) {
    self.include = include
  }
}

public struct OpenRouterChatSettings: Sendable, Equatable {
  public var logitBias: [Int: Double]?
  public var logprobs: OpenRouterLogprobs?
  public var parallelToolCalls: Bool?
  public var plugins: [OpenRouterPlugin]?
  public var webSearchOptions: OpenRouterWebSearchOptions?
  public var debug: OpenRouterDebugOptions?
  public var provider: OpenRouterProviderRouting?

  public var models: [String]?
  public var reasoning: OpenRouterReasoning?
  public var user: String?
  public var includeReasoning: Bool?
  public var extraBody: [String: JSONValue]?
  public var usage: OpenRouterUsageOption?

  public init(
    logitBias: [Int: Double]? = nil,
    logprobs: OpenRouterLogprobs? = nil,
    parallelToolCalls: Bool? = nil,
    plugins: [OpenRouterPlugin]? = nil,
    webSearchOptions: OpenRouterWebSearchOptions? = nil,
    debug: OpenRouterDebugOptions? = nil,
    provider: OpenRouterProviderRouting? = nil,
    models: [String]? = nil,
    reasoning: OpenRouterReasoning? = nil,
    user: String? = nil,
    includeReasoning: Bool? = nil,
    extraBody: [String: JSONValue]? = nil,
    usage: OpenRouterUsageOption? = nil
  ) {
    self.logitBias = logitBias
    self.logprobs = logprobs
    self.parallelToolCalls = parallelToolCalls
    self.plugins = plugins
    self.webSearchOptions = webSearchOptions
    self.debug = debug
    self.provider = provider
    self.models = models
    self.reasoning = reasoning
    self.user = user
    self.includeReasoning = includeReasoning
    self.extraBody = extraBody
    self.usage = usage
  }
}

public struct OpenRouterCompletionSettings: Sendable, Equatable {
  public var logitBias: [Int: Double]?
  public var logprobs: OpenRouterLogprobs?
  public var suffix: String?

  public var models: [String]?
  public var reasoning: OpenRouterReasoning?
  public var user: String?
  public var includeReasoning: Bool?
  public var extraBody: [String: JSONValue]?
  public var usage: OpenRouterUsageOption?

  public init(
    logitBias: [Int: Double]? = nil,
    logprobs: OpenRouterLogprobs? = nil,
    suffix: String? = nil,
    models: [String]? = nil,
    reasoning: OpenRouterReasoning? = nil,
    user: String? = nil,
    includeReasoning: Bool? = nil,
    extraBody: [String: JSONValue]? = nil,
    usage: OpenRouterUsageOption? = nil
  ) {
    self.logitBias = logitBias
    self.logprobs = logprobs
    self.suffix = suffix
    self.models = models
    self.reasoning = reasoning
    self.user = user
    self.includeReasoning = includeReasoning
    self.extraBody = extraBody
    self.usage = usage
  }
}

public struct OpenRouterEmbeddingSettings: Sendable, Equatable {
  public var user: String?
  public var provider: OpenRouterEmbeddingProviderRouting?
  public var models: [String]?
  public var reasoning: OpenRouterReasoning?
  public var includeReasoning: Bool?
  public var extraBody: [String: JSONValue]?
  public var usage: OpenRouterUsageOption?

  public init(
    user: String? = nil,
    provider: OpenRouterEmbeddingProviderRouting? = nil,
    models: [String]? = nil,
    reasoning: OpenRouterReasoning? = nil,
    includeReasoning: Bool? = nil,
    extraBody: [String: JSONValue]? = nil,
    usage: OpenRouterUsageOption? = nil
  ) {
    self.user = user
    self.provider = provider
    self.models = models
    self.reasoning = reasoning
    self.includeReasoning = includeReasoning
    self.extraBody = extraBody
    self.usage = usage
  }
}

public enum OpenRouterLogprobs: Sendable, Equatable {
  case enabled
  case top(Int)
  case disabled
}

public struct OpenRouterWebSearchOptions: Sendable, Equatable {
  public var maxResults: Int?
  public var searchPrompt: String?
  public var engine: String?

  public init(maxResults: Int? = nil, searchPrompt: String? = nil, engine: String? = nil) {
    self.maxResults = maxResults
    self.searchPrompt = searchPrompt
    self.engine = engine
  }
}

public struct OpenRouterDebugOptions: Sendable, Equatable {
  public var echoUpstreamBody: Bool?

  public init(echoUpstreamBody: Bool? = nil) {
    self.echoUpstreamBody = echoUpstreamBody
  }
}

public struct OpenRouterProviderRouting: Sendable, Equatable {
  public var order: [String]?
  public var allowFallbacks: Bool?
  public var requireParameters: Bool?
  public var dataCollection: String?
  public var only: [String]?
  public var ignore: [String]?
  public var quantizations: [String]?
  public var sort: String?
  public var maxPrice: OpenRouterMaxPrice?
  public var zdr: Bool?

  public init(
    order: [String]? = nil,
    allowFallbacks: Bool? = nil,
    requireParameters: Bool? = nil,
    dataCollection: String? = nil,
    only: [String]? = nil,
    ignore: [String]? = nil,
    quantizations: [String]? = nil,
    sort: String? = nil,
    maxPrice: OpenRouterMaxPrice? = nil,
    zdr: Bool? = nil
  ) {
    self.order = order
    self.allowFallbacks = allowFallbacks
    self.requireParameters = requireParameters
    self.dataCollection = dataCollection
    self.only = only
    self.ignore = ignore
    self.quantizations = quantizations
    self.sort = sort
    self.maxPrice = maxPrice
    self.zdr = zdr
  }
}

public struct OpenRouterEmbeddingProviderRouting: Sendable, Equatable {
  public var order: [String]?
  public var allowFallbacks: Bool?
  public var requireParameters: Bool?
  public var dataCollection: String?
  public var only: [String]?
  public var ignore: [String]?
  public var sort: String?
  public var maxPrice: OpenRouterMaxPrice?

  public init(
    order: [String]? = nil,
    allowFallbacks: Bool? = nil,
    requireParameters: Bool? = nil,
    dataCollection: String? = nil,
    only: [String]? = nil,
    ignore: [String]? = nil,
    sort: String? = nil,
    maxPrice: OpenRouterMaxPrice? = nil
  ) {
    self.order = order
    self.allowFallbacks = allowFallbacks
    self.requireParameters = requireParameters
    self.dataCollection = dataCollection
    self.only = only
    self.ignore = ignore
    self.sort = sort
    self.maxPrice = maxPrice
  }
}

public struct OpenRouterMaxPrice: Sendable, Equatable {
  public var prompt: JSONValue?
  public var completion: JSONValue?
  public var image: JSONValue?
  public var audio: JSONValue?
  public var request: JSONValue?

  public init(
    prompt: JSONValue? = nil,
    completion: JSONValue? = nil,
    image: JSONValue? = nil,
    audio: JSONValue? = nil,
    request: JSONValue? = nil
  ) {
    self.prompt = prompt
    self.completion = completion
    self.image = image
    self.audio = audio
    self.request = request
  }
}

public enum OpenRouterPlugin: Sendable, Equatable, Encodable {
  case web(id: String, maxResults: Int? = nil, searchPrompt: String? = nil, engine: String? = nil)
  case fileParser(id: String, maxFiles: Int? = nil, pdfEngine: String? = nil)
  case moderation(id: String)

  enum CodingKeys: String, CodingKey {
    case id
    case maxResults = "max_results"
    case searchPrompt = "search_prompt"
    case engine
    case maxFiles = "max_files"
    case pdf
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .web(let id, let maxResults, let searchPrompt, let engine):
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(maxResults, forKey: .maxResults)
      try container.encodeIfPresent(searchPrompt, forKey: .searchPrompt)
      try container.encodeIfPresent(engine, forKey: .engine)
    case .fileParser(let id, let maxFiles, let pdfEngine):
      try container.encode(id, forKey: .id)
      try container.encodeIfPresent(maxFiles, forKey: .maxFiles)
      if let pdfEngine {
        try container.encode(["engine": pdfEngine], forKey: .pdf)
      }
    case .moderation(let id):
      try container.encode(id, forKey: .id)
    }
  }
}
