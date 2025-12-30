import Foundation
import AIKitProviders

public enum OpenRouterCompatibility: String, Sendable {
  case strict
  case compatible
}

public struct OpenRouterProviderSettings: Sendable {
  public var baseURL: String?
  public var baseUrl: String?
  public var apiKey: String?
  public var headers: [String: String]?
  public var compatibility: OpenRouterCompatibility?
  public var transport: HTTPTransport?
  public var extraBody: [String: JSONValue]?
  public var apiKeys: [String: String]?

  public init(
    baseURL: String? = nil,
    baseUrl: String? = nil,
    apiKey: String? = nil,
    headers: [String: String]? = nil,
    compatibility: OpenRouterCompatibility? = nil,
    transport: HTTPTransport? = nil,
    extraBody: [String: JSONValue]? = nil,
    apiKeys: [String: String]? = nil
  ) {
    self.baseURL = baseURL
    self.baseUrl = baseUrl
    self.apiKey = apiKey
    self.headers = headers
    self.compatibility = compatibility
    self.transport = transport
    self.extraBody = extraBody
    self.apiKeys = apiKeys
  }
}

public protocol OpenRouterProvider: Sendable {
  func languageModel(_ modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings) -> any LanguageModel
  func chat(_ modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings) -> any LanguageModel
  func completion(_ modelId: OpenRouterCompletionModelID, settings: OpenRouterCompletionSettings) -> any LanguageModel
  func textEmbeddingModel(_ modelId: OpenRouterEmbeddingModelID, settings: OpenRouterEmbeddingSettings) -> any EmbeddingModel

  @available(*, deprecated, message: "Use textEmbeddingModel(_:settings:) instead.")
  func embedding(_ modelId: OpenRouterEmbeddingModelID, settings: OpenRouterEmbeddingSettings) -> any EmbeddingModel
}

public struct OpenRouterProviderClient: OpenRouterProvider, Sendable {
  public let settings: OpenRouterProviderSettings

  public init(settings: OpenRouterProviderSettings = .init()) {
    self.settings = settings
  }

  public func callAsFunction(_ modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings = .init()) -> any LanguageModel {
    languageModel(modelId, settings: settings)
  }

  public func callAsFunction(
    _ modelId: OpenRouterCompletionModelID,
    completionSettings: OpenRouterCompletionSettings = .init()
  ) -> any LanguageModel {
    completion(modelId, settings: completionSettings)
  }

  public func languageModel(_ modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings = .init()) -> any LanguageModel {
    if modelId == "openai/gpt-3.5-turbo-instruct" {
      return completion(modelId, settings: .init())
    }
    return chat(modelId, settings: settings)
  }

  public func chat(_ modelId: OpenRouterChatModelID, settings: OpenRouterChatSettings = .init()) -> any LanguageModel {
    OpenRouterChatLanguageModel(
      modelId: modelId,
      settings: settings,
      config: makeChatConfig()
    )
  }

  public func completion(
    _ modelId: OpenRouterCompletionModelID,
    settings: OpenRouterCompletionSettings = .init()
  ) -> any LanguageModel {
    OpenRouterCompletionLanguageModel(
      modelId: modelId,
      settings: settings,
      config: makeCompletionConfig()
    )
  }

  public func textEmbeddingModel(
    _ modelId: OpenRouterEmbeddingModelID,
    settings: OpenRouterEmbeddingSettings = .init()
  ) -> any EmbeddingModel {
    OpenRouterEmbeddingModel(
      modelId: modelId,
      settings: settings,
      config: makeEmbeddingConfig()
    )
  }

  public func embedding(
    _ modelId: OpenRouterEmbeddingModelID,
    settings: OpenRouterEmbeddingSettings = .init()
  ) -> any EmbeddingModel {
    textEmbeddingModel(modelId, settings: settings)
  }

  private func makeChatConfig() -> OpenRouterChatConfig {
    OpenRouterChatConfig(
      provider: "openrouter.chat",
      compatibility: settings.compatibility ?? .compatible,
      headers: headersProvider(),
      url: urlProvider(),
      transport: settings.transport ?? OpenRouterURLSessionTransport(),
      extraBody: settings.extraBody
    )
  }

  private func makeCompletionConfig() -> OpenRouterCompletionConfig {
    OpenRouterCompletionConfig(
      provider: "openrouter.completion",
      compatibility: settings.compatibility ?? .compatible,
      headers: headersProvider(),
      url: urlProvider(),
      transport: settings.transport ?? OpenRouterURLSessionTransport(),
      extraBody: settings.extraBody
    )
  }

  private func makeEmbeddingConfig() -> OpenRouterEmbeddingConfig {
    OpenRouterEmbeddingConfig(
      provider: "openrouter.embedding",
      headers: headersProvider(),
      url: urlProvider(),
      transport: settings.transport ?? OpenRouterURLSessionTransport(),
      extraBody: settings.extraBody
    )
  }

  private func headersProvider() -> @Sendable () -> [String: String] {
    return {
      let apiKey = try? loadOpenRouterAPIKey(apiKey: settings.apiKey)
      var headers: [String: String] = [:]
      if let apiKey {
        headers["Authorization"] = "Bearer \(apiKey)"
      }
      if let custom = settings.headers {
        for (key, value) in custom { headers[key] = value }
      }
      if let apiKeys = settings.apiKeys, apiKeys.isEmpty == false {
        if let data = try? JSONSerialization.data(withJSONObject: apiKeys, options: []),
           let json = String(data: data, encoding: .utf8) {
          headers["X-Provider-API-Keys"] = json
        }
      }
      headers = withUserAgentSuffix(headers, suffixParts: ["ai-sdk/openrouter/\(OpenRouterVersion.current)"])
      return headers
    }
  }

  private func urlProvider() -> @Sendable (String) -> String {
    let base = withoutTrailingSlash(settings.baseURL ?? settings.baseUrl ?? "https://openrouter.ai/api/v1")
    return { path in
      "\(base)\(path)"
    }
  }
}

public func createOpenRouter(_ settings: OpenRouterProviderSettings = .init()) -> OpenRouterProviderClient {
  OpenRouterProviderClient(settings: settings)
}

public let openrouter = OpenRouterProviderClient(settings: .init(compatibility: .strict))
