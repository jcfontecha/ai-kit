import Foundation
import FoundationModels
import AIKitProviders

public struct AppleLanguageModelSettings: Sendable {
  public var modelID: String
  public var useCase: SystemLanguageModel.UseCase
  public var guardrails: SystemLanguageModel.Guardrails
  public var includeSchemaInPrompt: Bool
  public var includeToolSchemaInInstructions: Bool

  public init(
    modelID: String = "apple/system",
    useCase: SystemLanguageModel.UseCase = .general,
    guardrails: SystemLanguageModel.Guardrails = .default,
    includeSchemaInPrompt: Bool = true,
    includeToolSchemaInInstructions: Bool = true
  ) {
    self.modelID = modelID
    self.useCase = useCase
    self.guardrails = guardrails
    self.includeSchemaInPrompt = includeSchemaInPrompt
    self.includeToolSchemaInInstructions = includeToolSchemaInInstructions
  }
}

public struct AppleProviderSettings: Sendable {
  public var languageModel: AppleLanguageModelSettings

  public init(languageModel: AppleLanguageModelSettings = .init()) {
    self.languageModel = languageModel
  }
}

public protocol AppleProvider: Sendable {
  func languageModel() -> any LanguageModel
  func languageModel(_ settings: AppleLanguageModelSettings) -> any LanguageModel
}

public struct AppleProviderClient: AppleProvider, Sendable {
  public let settings: AppleProviderSettings

  public init(settings: AppleProviderSettings = .init()) {
    self.settings = settings
  }

  public func languageModel() -> any LanguageModel {
    AppleLanguageModel(settings: settings.languageModel)
  }

  public func languageModel(_ settings: AppleLanguageModelSettings) -> any LanguageModel {
    AppleLanguageModel(settings: settings)
  }
}

public func createApple(_ settings: AppleProviderSettings = .init()) -> AppleProviderClient {
  AppleProviderClient(settings: settings)
}

public let apple = AppleProviderClient(settings: .init())
