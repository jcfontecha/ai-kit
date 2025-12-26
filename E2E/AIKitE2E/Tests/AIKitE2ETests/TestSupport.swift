import Foundation
import AIKit

final class RecordingLanguageModel: @unchecked Sendable, LanguageModel {
  let id: String
  let capabilities: ModelCapabilities
  let supportedURLs: SupportedURLPatterns

  private let state = State()
  private let generateHandler: @Sendable (ModelRequest) async throws -> ModelResponse
  private let streamHandler: @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error>

  actor State {
    var requests: [ModelRequest] = []
    func record(_ request: ModelRequest) { requests.append(request) }
    func snapshot() -> [ModelRequest] { requests }
  }

  init(
    id: String = "recording-model",
    capabilities: ModelCapabilities = [],
    supportedURLs: SupportedURLPatterns = [:],
    generate: @escaping @Sendable (ModelRequest) async throws -> ModelResponse,
    stream: @escaping @Sendable (ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> = { _ in
      AsyncThrowingStream(ModelStreamPart.self) { $0.finish() }
    }
  ) {
    self.id = id
    self.capabilities = capabilities
    self.supportedURLs = supportedURLs
    self.generateHandler = generate
    self.streamHandler = stream
  }

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    await state.record(request)
    return try await generateHandler(request)
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    Task { await state.record(request) }
    return streamHandler(request)
  }

  func recordedRequests() async -> [ModelRequest] {
    await state.snapshot()
  }
}

final class QueuedLanguageModel: @unchecked Sendable, LanguageModel {
  let id: String
  let capabilities: ModelCapabilities
  let supportedURLs: SupportedURLPatterns

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
        return { _ in throw AIKitError.invalidConfiguration("QueuedLanguageModel: no generate handler") }
      }
      return generateQueue.removeFirst()
    }
  }

  init(
    id: String = "queued-model",
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

  func generate(_ request: ModelRequest) async throws -> ModelResponse {
    await state.record(request)
    let handler = await state.nextHandler()
    return try await handler(request)
  }

  func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelStreamPart, Error> {
    Task { await state.record(request) }
    return streamHandler(request)
  }
}

func makeStream(_ parts: [ModelStreamPart]) -> AsyncThrowingStream<ModelStreamPart, Error> {
  AsyncThrowingStream(ModelStreamPart.self) { continuation in
    for part in parts { continuation.yield(part) }
    continuation.finish()
  }
}

