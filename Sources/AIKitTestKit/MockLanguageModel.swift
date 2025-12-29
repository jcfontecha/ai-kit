import Foundation
import AIKitProviders

private struct UnsafeSendable<Value>: @unchecked Sendable {
  let value: Value
}

private final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withLock<T>(_ body: (inout Value) -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }

  func get() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

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
    let semaphoreBox = UnsafeSendable(value: semaphore)
    let resultBox = UnsafeSendable(value: Locked<[ModelRequest]>([]))
    Task {
      let requests = await state.requests
      resultBox.value.withLock { $0 = requests }
      semaphoreBox.value.signal()
    }
    semaphore.wait()
    return resultBox.value.get()
  }
}
