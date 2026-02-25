import Foundation

public enum OpenAIServiceTier: String, Sendable {
  case auto
  case flex
  case priority
  case `default`
}

public enum OpenAISystemMessageMode: String, Sendable {
  case system
  case developer
  case remove
}

public enum OpenAIReasoningEffort: String, Sendable {
  case none
  case minimal
  case low
  case medium
  case high
  case xhigh
}

public enum OpenAITextVerbosity: String, Sendable {
  case low
  case medium
  case high
}

public enum OpenAIPromptCacheRetention: String, Sendable {
  case inMemory = "in_memory"
  case hours24 = "24h"
}

public struct OpenAIChatLanguageModelOptions: Sendable {
  public var logitBias: [String: Double]?
  public var logprobs: LogProbs?
  public var parallelToolCalls: Bool?
  public var user: String?
  public var reasoningEffort: OpenAIReasoningEffort?
  public var maxCompletionTokens: Int?
  public var store: Bool?
  public var metadata: [String: String]?
  public var prediction: [String: String]?
  public var serviceTier: OpenAIServiceTier?
  public var strictJsonSchema: Bool?
  public var textVerbosity: OpenAITextVerbosity?
  public var promptCacheKey: String?
  public var promptCacheRetention: OpenAIPromptCacheRetention?
  public var safetyIdentifier: String?
  public var systemMessageMode: OpenAISystemMessageMode?
  public var forceReasoning: Bool?

  public init(
    logitBias: [String: Double]? = nil,
    logprobs: LogProbs? = nil,
    parallelToolCalls: Bool? = nil,
    user: String? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    maxCompletionTokens: Int? = nil,
    store: Bool? = nil,
    metadata: [String: String]? = nil,
    prediction: [String: String]? = nil,
    serviceTier: OpenAIServiceTier? = nil,
    strictJsonSchema: Bool? = nil,
    textVerbosity: OpenAITextVerbosity? = nil,
    promptCacheKey: String? = nil,
    promptCacheRetention: OpenAIPromptCacheRetention? = nil,
    safetyIdentifier: String? = nil,
    systemMessageMode: OpenAISystemMessageMode? = nil,
    forceReasoning: Bool? = nil
  ) {
    self.logitBias = logitBias
    self.logprobs = logprobs
    self.parallelToolCalls = parallelToolCalls
    self.user = user
    self.reasoningEffort = reasoningEffort
    self.maxCompletionTokens = maxCompletionTokens
    self.store = store
    self.metadata = metadata
    self.prediction = prediction
    self.serviceTier = serviceTier
    self.strictJsonSchema = strictJsonSchema
    self.textVerbosity = textVerbosity
    self.promptCacheKey = promptCacheKey
    self.promptCacheRetention = promptCacheRetention
    self.safetyIdentifier = safetyIdentifier
    self.systemMessageMode = systemMessageMode
    self.forceReasoning = forceReasoning
  }

  public enum LogProbs: Sendable {
    case enabled(Bool)
    case topN(Int)
  }
}

public struct OpenAIResponsesProviderOptions: Sendable {
  public var conversation: String?
  public var include: [String]?
  public var instructions: String?
  public var logprobs: LogProbs?
  public var maxToolCalls: Int?
  public var metadata: [String: String]?
  public var parallelToolCalls: Bool?
  public var previousResponseID: String?
  public var promptCacheKey: String?
  public var promptCacheRetention: OpenAIPromptCacheRetention?
  public var reasoningEffort: OpenAIReasoningEffort?
  public var reasoningSummary: String?
  public var safetyIdentifier: String?
  public var serviceTier: OpenAIServiceTier?
  public var store: Bool?
  public var strictJsonSchema: Bool?
  public var textVerbosity: OpenAITextVerbosity?
  public var truncation: Truncation?
  public var user: String?
  public var systemMessageMode: OpenAISystemMessageMode?
  public var forceReasoning: Bool?

  public init(
    conversation: String? = nil,
    include: [String]? = nil,
    instructions: String? = nil,
    logprobs: LogProbs? = nil,
    maxToolCalls: Int? = nil,
    metadata: [String: String]? = nil,
    parallelToolCalls: Bool? = nil,
    previousResponseID: String? = nil,
    promptCacheKey: String? = nil,
    promptCacheRetention: OpenAIPromptCacheRetention? = nil,
    reasoningEffort: OpenAIReasoningEffort? = nil,
    reasoningSummary: String? = nil,
    safetyIdentifier: String? = nil,
    serviceTier: OpenAIServiceTier? = nil,
    store: Bool? = nil,
    strictJsonSchema: Bool? = nil,
    textVerbosity: OpenAITextVerbosity? = nil,
    truncation: Truncation? = nil,
    user: String? = nil,
    systemMessageMode: OpenAISystemMessageMode? = nil,
    forceReasoning: Bool? = nil
  ) {
    self.conversation = conversation
    self.include = include
    self.instructions = instructions
    self.logprobs = logprobs
    self.maxToolCalls = maxToolCalls
    self.metadata = metadata
    self.parallelToolCalls = parallelToolCalls
    self.previousResponseID = previousResponseID
    self.promptCacheKey = promptCacheKey
    self.promptCacheRetention = promptCacheRetention
    self.reasoningEffort = reasoningEffort
    self.reasoningSummary = reasoningSummary
    self.safetyIdentifier = safetyIdentifier
    self.serviceTier = serviceTier
    self.store = store
    self.strictJsonSchema = strictJsonSchema
    self.textVerbosity = textVerbosity
    self.truncation = truncation
    self.user = user
    self.systemMessageMode = systemMessageMode
    self.forceReasoning = forceReasoning
  }

  public enum LogProbs: Sendable {
    case enabled(Bool)
    case topN(Int)
  }

  public enum Truncation: String, Sendable {
    case auto
    case disabled
  }
}

public struct OpenAILanguageModelCapabilities: Sendable {
  public var isReasoningModel: Bool
  public var systemMessageMode: OpenAISystemMessageMode
  public var supportsFlexProcessing: Bool
  public var supportsPriorityProcessing: Bool
  public var supportsNonReasoningParameters: Bool

  public init(
    isReasoningModel: Bool,
    systemMessageMode: OpenAISystemMessageMode,
    supportsFlexProcessing: Bool,
    supportsPriorityProcessing: Bool,
    supportsNonReasoningParameters: Bool
  ) {
    self.isReasoningModel = isReasoningModel
    self.systemMessageMode = systemMessageMode
    self.supportsFlexProcessing = supportsFlexProcessing
    self.supportsPriorityProcessing = supportsPriorityProcessing
    self.supportsNonReasoningParameters = supportsNonReasoningParameters
  }
}

public func getOpenAILanguageModelCapabilities(
  modelID: String,
  forceReasoning: Bool? = nil,
  systemMessageModeOverride: OpenAISystemMessageMode? = nil
) -> OpenAILanguageModelCapabilities {
  let isReasoningModel = forceReasoning ?? false
  let systemMessageMode = systemMessageModeOverride ?? (isReasoningModel ? .developer : .system)
  return .init(
    isReasoningModel: isReasoningModel,
    systemMessageMode: systemMessageMode,
    supportsFlexProcessing: false,
    supportsPriorityProcessing: false,
    supportsNonReasoningParameters: false
  )
}
