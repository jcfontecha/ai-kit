import Foundation
import AIKitProviders

public struct FalProviderSettings: Sendable {
  public var apiKey: String?
  public var baseURL: String?
  public var headers: [String: String]?
  public var transport: HTTPTransport?

  public init(
    apiKey: String? = nil,
    baseURL: String? = nil,
    headers: [String: String]? = nil,
    transport: HTTPTransport? = nil
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.headers = headers
    self.transport = transport
  }
}

public protocol FalProvider: Sendable {
  func image(_ modelId: String) -> any ImageModel
  func imageModel(_ modelId: String) -> any ImageModel
}

public struct FalProviderClient: FalProvider, Sendable {
  public let settings: FalProviderSettings

  public init(settings: FalProviderSettings = .init()) {
    self.settings = settings
  }

  public func image(_ modelId: String) -> any ImageModel {
    FalImageModel(
      modelId: modelId,
      config: FalImageModelConfig(
        baseURL: withoutTrailingSlash(settings.baseURL ?? "https://fal.run"),
        apiKey: settings.apiKey,
        headers: providerHeaders(),
        transport: settings.transport ?? FalURLSessionTransport()
      )
    )
  }

  public func imageModel(_ modelId: String) -> any ImageModel {
    image(modelId)
  }

  private func providerHeaders() -> @Sendable () -> [String: String] {
    return {
      var headers: [String: String] = [:]
      if let apiKey = loadFalAPIKey(apiKey: settings.apiKey) {
        headers["Authorization"] = "Key \(apiKey)"
      }
      if let custom = settings.headers {
        for (key, value) in custom { headers[key] = value }
      }
      return withUserAgentSuffix(headers, suffixParts: ["ai-sdk/fal/\(FalVersion.current)"])
    }
  }
}

public func createFal(_ settings: FalProviderSettings = .init()) -> FalProviderClient {
  FalProviderClient(settings: settings)
}

public let fal = FalProviderClient(settings: .init())
