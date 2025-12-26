import Foundation
import AIKitProviders

public struct ReplicateProviderSettings: Sendable {
  public var apiToken: String?
  public var baseURL: String?
  public var headers: [String: String]?
  public var transport: HTTPTransport?

  public init(
    apiToken: String? = nil,
    baseURL: String? = nil,
    headers: [String: String]? = nil,
    transport: HTTPTransport? = nil
  ) {
    self.apiToken = apiToken
    self.baseURL = baseURL
    self.headers = headers
    self.transport = transport
  }
}

public protocol ReplicateProvider: Sendable {
  func image(_ modelId: String) -> any ImageModel
  func imageModel(_ modelId: String) -> any ImageModel
}

public struct ReplicateProviderClient: ReplicateProvider, Sendable {
  public let settings: ReplicateProviderSettings

  public init(settings: ReplicateProviderSettings = .init()) {
    self.settings = settings
  }

  public func image(_ modelId: String) -> any ImageModel {
    ReplicateImageModel(
      modelId: modelId,
      config: ReplicateImageModelConfig(
        baseURL: withoutTrailingSlash(settings.baseURL ?? "https://api.replicate.com/v1"),
        headers: providerHeaders(),
        transport: settings.transport ?? ReplicateURLSessionTransport()
      )
    )
  }

  public func imageModel(_ modelId: String) -> any ImageModel {
    image(modelId)
  }

  private func providerHeaders() -> @Sendable () -> [String: String] {
    return {
      var headers: [String: String] = [:]
      if let token = settings.apiToken {
        headers["Authorization"] = "Bearer \(token)"
      }
      if let custom = settings.headers {
        for (key, value) in custom { headers[key] = value }
      }
      return withUserAgentSuffix(headers, suffixParts: ["ai-sdk/replicate/\(ReplicateVersion.current)"])
    }
  }
}

public func createReplicate(_ settings: ReplicateProviderSettings = .init()) -> ReplicateProviderClient {
  ReplicateProviderClient(settings: settings)
}

public let replicate = ReplicateProviderClient(settings: .init())

