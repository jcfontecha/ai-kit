import Foundation
import AIKitProviders

public struct PrepareStepContext: Sendable {
  public var steps: [StepResult]
  public var stepNumber: Int
  public var model: any LanguageModel
  public var messages: [ModelMessage]
  public var experimentalContext: AnySendable?

  public init(
    steps: [StepResult],
    stepNumber: Int,
    model: any LanguageModel,
    messages: [ModelMessage],
    experimentalContext: AnySendable? = nil
  ) {
    self.steps = steps
    self.stepNumber = stepNumber
    self.model = model
    self.messages = messages
    self.experimentalContext = experimentalContext
  }
}

public struct PrepareStepResult: Sendable {
  public var model: (any LanguageModel)?
  public var toolChoice: ToolChoice?
  public var activeTools: [String]?
  public var system: SystemPrompt?
  public var messages: [ModelMessage]?
  public var experimentalContext: AnySendable?
  public var providerOptions: ProviderOptions?

  public init(
    model: (any LanguageModel)? = nil,
    toolChoice: ToolChoice? = nil,
    activeTools: [String]? = nil,
    system: SystemPrompt? = nil,
    messages: [ModelMessage]? = nil,
    experimentalContext: AnySendable? = nil,
    providerOptions: ProviderOptions? = nil
  ) {
    self.model = model
    self.toolChoice = toolChoice
    self.activeTools = activeTools
    self.system = system
    self.messages = messages
    self.experimentalContext = experimentalContext
    self.providerOptions = providerOptions
  }
}

public typealias PrepareStepFunction = @Sendable (PrepareStepContext) async -> PrepareStepResult?

