import Foundation
import AIKitProviders

public protocol OpenAIProvider: Sendable {
  subscript(modelId: OpenAIResponsesModelID) -> any LanguageModel { get }

  func languageModel(_ modelId: OpenAIResponsesModelID) -> any LanguageModel
  func chat(_ modelId: OpenAIChatModelID) -> any LanguageModel
  func responses(_ modelId: OpenAIResponsesModelID) -> any LanguageModel
  func completion(_ modelId: OpenAICompletionModelID) -> any LanguageModel

  func embedding(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel
  func embeddingModel(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel

  @available(*, deprecated, message: "Use embedding(_:) instead.")
  func textEmbedding(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel

  @available(*, deprecated, message: "Use embeddingModel(_:) instead.")
  func textEmbeddingModel(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel

  func image(_ modelId: OpenAIImageModelID) -> any ImageModel
  func imageModel(_ modelId: OpenAIImageModelID) -> any ImageModel

  func transcription(_ modelId: OpenAITranscriptionModelID) -> any TranscriptionModel
  func speech(_ modelId: OpenAISpeechModelID) -> any SpeechModel

  var tools: OpenAITools { get }
}

public struct OpenAIProviderSettings: Sendable {
  public var baseURL: URL?
  public var apiKey: String?
  public var organization: String?
  public var project: String?
  public var headers: [String: String]?
  public var name: String?
  public var transport: OpenAITransport?

  public init(
    baseURL: URL? = nil,
    apiKey: String? = nil,
    organization: String? = nil,
    project: String? = nil,
    headers: [String: String]? = nil,
    name: String? = nil,
    transport: OpenAITransport? = nil
  ) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.organization = organization
    self.project = project
    self.headers = headers
    self.name = name
    self.transport = transport
  }
}

public typealias OpenAITransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

public struct OpenAIProviderClient: OpenAIProvider, Sendable {
  public let settings: OpenAIProviderSettings
  public let tools: OpenAITools = .init()

  public init(settings: OpenAIProviderSettings = .init()) {
    self.settings = settings
  }

  public subscript(modelId: OpenAIResponsesModelID) -> any LanguageModel {
    languageModel(modelId)
  }

  public func languageModel(_ modelId: OpenAIResponsesModelID) -> any LanguageModel {
    UnimplementedLanguageModel(modelID: modelId.rawValue)
  }

  public func chat(_ modelId: OpenAIChatModelID) -> any LanguageModel {
    UnimplementedLanguageModel(modelID: modelId.rawValue)
  }

  public func responses(_ modelId: OpenAIResponsesModelID) -> any LanguageModel {
    UnimplementedLanguageModel(modelID: modelId.rawValue)
  }

  public func completion(_ modelId: OpenAICompletionModelID) -> any LanguageModel {
    UnimplementedLanguageModel(modelID: modelId.rawValue)
  }

  public func embedding(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel {
    UnimplementedEmbeddingModel(modelID: modelId.rawValue)
  }

  public func embeddingModel(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel {
    embedding(modelId)
  }

  public func textEmbedding(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel {
    embedding(modelId)
  }

  public func textEmbeddingModel(_ modelId: OpenAIEmbeddingModelID) -> any EmbeddingModel {
    embedding(modelId)
  }

  public func image(_ modelId: OpenAIImageModelID) -> any ImageModel {
    UnimplementedImageModel(modelID: modelId.rawValue)
  }

  public func imageModel(_ modelId: OpenAIImageModelID) -> any ImageModel {
    image(modelId)
  }

  public func transcription(_ modelId: OpenAITranscriptionModelID) -> any TranscriptionModel {
    UnimplementedTranscriptionModel(modelID: modelId.rawValue)
  }

  public func speech(_ modelId: OpenAISpeechModelID) -> any SpeechModel {
    UnimplementedSpeechModel(modelID: modelId.rawValue)
  }
}

public func createOpenAI(_ settings: OpenAIProviderSettings = .init()) -> OpenAIProvider {
  OpenAIProviderClient(settings: settings)
}

public let openai: OpenAIProvider = createOpenAI()

private struct UnimplementedLanguageModel: LanguageModel, Sendable {
  let id: String
  let capabilities: ModelCapabilities = []
  let supportedURLs: SupportedURLPatterns = [:]

  init(modelID: String) {
    self.id = modelID
  }

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    throw AIKitError.notImplemented("OpenAI language model implementation is not available yet.")
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { $0.finish() }
  }
}

private struct UnimplementedEmbeddingModel: EmbeddingModel, Sendable {
  let id: String

  init(modelID: String) {
    self.id = modelID
  }

  func embed(_ request: EmbeddingRequest) async throws -> EmbeddingResponse {
    throw AIKitError.notImplemented("OpenAI embedding model implementation is not available yet.")
  }
}

private struct UnimplementedImageModel: ImageModel, Sendable {
  let id: String

  init(modelID: String) {
    self.id = modelID
  }

  func generate(_ request: ImageRequest) async throws -> ImageResponse {
    throw AIKitError.notImplemented("OpenAI image model implementation is not available yet.")
  }
}

private struct UnimplementedSpeechModel: SpeechModel, Sendable {
  let id: String

  init(modelID: String) {
    self.id = modelID
  }

  func speak(_ request: SpeechRequest) async throws -> SpeechResponse {
    throw AIKitError.notImplemented("OpenAI speech model implementation is not available yet.")
  }
}

private struct UnimplementedTranscriptionModel: TranscriptionModel, Sendable {
  let id: String

  init(modelID: String) {
    self.id = modelID
  }

  func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResponse {
    throw AIKitError.notImplemented("OpenAI transcription model implementation is not available yet.")
  }
}
