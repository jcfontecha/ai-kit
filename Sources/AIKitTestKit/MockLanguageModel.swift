import Foundation
import AIKitCore
import AIKitProviders

public final class MockLanguageModel: @unchecked Sendable, LanguageModel {
  public let id: String
  public let capabilities: ModelCapabilities
  public let supportedURLs: SupportedURLPatterns

  private let state: State
  private let streamHandler: @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error>

  actor State {
    var requests: [ModelRequest] = []
    var generateQueue: [@Sendable (ModelRequest) async throws -> ModelResponse]

    init(generateQueue: [@Sendable (ModelRequest) async throws -> ModelResponse]) {
      self.generateQueue = generateQueue
    }

    func record(_ request: ModelRequest) {
      requests.append(request)
    }

    func nextHandler() -> (@Sendable (ModelRequest) async throws -> ModelResponse) {
      if generateQueue.isEmpty {
        return { _ in throw AIKitError.invalidConfiguration("MockLanguageModel: no generate handler") }
      }
      return generateQueue.removeFirst()
    }

    func setGenerateQueue(_ responses: [ModelResponse]) {
      generateQueue = responses.map { response in
        { _ in response }
      }
    }
  }

  private init(
    id: String = "mock-model",
    capabilities: ModelCapabilities = [],
    supportedURLs: SupportedURLPatterns = [:],
    generateQueue: [@Sendable (ModelRequest) async throws -> ModelResponse],
    stream: @escaping @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> = { _ in
      AsyncThrowingStream(ModelStreamPart.self) { $0.finish() }
    }
  ) {
    self.id = id
    self.capabilities = capabilities
    self.supportedURLs = supportedURLs
    self.state = State(generateQueue: generateQueue)
    self.streamHandler = stream
  }

  public convenience init(
    id: String = "mock-model",
    capabilities: ModelCapabilities = [],
    supportedURLs: SupportedURLPatterns = [:],
    generate: @escaping @Sendable (ModelRequest) async throws -> ModelResponse,
    stream: @escaping @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> = { _ in
      AsyncThrowingStream(ModelStreamPart.self) { $0.finish() }
    }
  ) {
    self.init(
      id: id,
      capabilities: capabilities,
      supportedURLs: supportedURLs,
      generateQueue: [generate],
      stream: stream
    )
  }

  public convenience init(
    id: String = "mock-model",
    capabilities: ModelCapabilities = [],
    supportedURLs: SupportedURLPatterns = [:],
    responses: [ModelResponse]
  ) {
    self.init(
      id: id,
      capabilities: capabilities,
      supportedURLs: supportedURLs,
      generateQueue: responses.map { response in
        { _ in response }
      }
    )
  }

  public func generate(_ request: ModelRequest) async throws -> ModelResponse {
    await state.record(request)
    let handler = await state.nextHandler()
    return try await handler(request)
  }

  public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    Task { await state.record(request) }
    return streamHandler(request)
  }

  public func recordedRequests() -> [ModelRequest] {
    let semaphore = DispatchSemaphore(value: 0)
    var result: [ModelRequest] = []
    Task {
      result = await state.requests
      semaphore.signal()
    }
    semaphore.wait()
    return result
  }
}
