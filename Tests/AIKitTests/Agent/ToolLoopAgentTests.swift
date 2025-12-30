import XCTest
import AIKitProviders
import AIKitTestKit
@testable @_spi(Advanced) import AIKit

final class AgentTests: XCTestCase {
  private struct CallOptions: Sendable, Equatable {
    let value: String
  }

  private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ModelRequest?

    func set(_ newValue: ModelRequest) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> ModelRequest? {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private final class DownloadRequestsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [DownloadRequest] = []

    func set(_ newValue: [DownloadRequest]) {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }

    func get() -> [DownloadRequest] {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private static func response(
    finishReason: FinishReason = .stop,
    content: [ModelContentPart] = [.text("reply", metadata: nil)]
  ) -> ModelResponse {
    .init(
      content: content,
      finishReason: finishReason,
      rawFinishReason: finishReason.rawValue,
      usage: .init(
        inputTokens: .init(total: 3, noCache: 3, cacheRead: nil, cacheWrite: nil),
        outputTokens: .init(total: 10, text: 10, reasoning: nil)
      ),
      warnings: [],
      request: .init(),
      response: .init(),
      providerMetadata: nil
    )
  }

  private static func makeStream(_ parts: [ModelStreamPart]) -> AsyncThrowingStream<ModelStreamPart, Error> {
    AsyncThrowingStream(ModelStreamPart.self) { continuation in
      for part in parts {
        continuation.yield(part)
      }
      continuation.finish()
    }
  }

  func testGenerate_usesPrepareCall() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<CallOptions, Output.Text>(
      model: model,
      toolChoice: .auto,
      output: Output.text(),
      prepareCall: { call in
        var updated = call
        updated.toolChoice = .none
        return updated
      }
    )

    _ = try await agent.generate(prompt: "Hello, world!", options: .init(value: "test"))

    XCTAssertEqual(requestBox.get()?.toolChoice, .some(.none))
  }

  func testGenerate_prepareCallInjectsProviderOptions() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<CallOptions, Output.Text>(
      model: model,
      output: Output.text(),
      prepareCall: { call in
        var updated = call
        updated.providerOptions = ["test": ["value": .string(call.options?.value ?? "missing")]]
        return updated
      }
    )

    _ = try await agent.generate(prompt: "Hello, world!", options: .init(value: "test"))

    XCTAssertEqual(
      requestBox.get()?.providerOptions,
      ["test": ["value": .string("test")]]
    )
  }

  func testGenerate_passesCancellationToken() async throws {
    let requestBox = RequestBox()
    let token = CancellationToken()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<Never, Output.Text>(
      model: model,
      cancellationToken: token,
      output: Output.text()
    )

    _ = try await agent.generate(prompt: "Hello, world!")

    XCTAssertTrue(requestBox.get()?.cancellationToken === token)
  }

  func testGenerate_instructionsString() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<Never, Output.Text>(
      model: model,
      instructions: .text("INSTRUCTIONS"),
      output: Output.text()
    )

    _ = try await agent.generate(prompt: "Hello, world!")

    XCTAssertEqual(
      requestBox.get()?.messages,
      [
        .system("INSTRUCTIONS"),
        .user("Hello, world!")
      ]
    )
  }

  func testGenerate_instructionsSystemMessage() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let systemMessage = ModelMessage(
      role: .system,
      content: [.text("INSTRUCTIONS")],
      providerOptions: ["test": ["value": .string("test")]]
    )

    let agent = Agent<Never, Output.Text>(
      model: model,
      instructions: .message(systemMessage),
      output: Output.text()
    )

    _ = try await agent.generate(prompt: "Hello, world!")

    XCTAssertEqual(
      requestBox.get()?.messages,
      [
        systemMessage,
        .user("Hello, world!")
      ]
    )
  }

  func testGenerate_instructionsArray() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let systemMessages = [
      ModelMessage(
        role: .system,
        content: [.text("INSTRUCTIONS")],
        providerOptions: ["test": ["value": .string("test")]]
      ),
      ModelMessage(
        role: .system,
        content: [.text("INSTRUCTIONS 2")],
        providerOptions: ["test": ["value": .string("test 2")]]
      )
    ]

    let agent = Agent<Never, Output.Text>(
      model: model,
      instructions: .messages(systemMessages),
      output: Output.text()
    )

    _ = try await agent.generate(prompt: "Hello, world!")

    XCTAssertEqual(
      requestBox.get()?.messages,
      systemMessages + [.user("Hello, world!")]
    )
  }

  func testGenerate_downloadsImageURLsFromMessages() async throws {
    let requestBox = RequestBox()
    let downloadsBox = DownloadRequestsBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<Never, Output.Text>(
      model: model,
      download: { requests in
        downloadsBox.set(requests)
        return [DownloadedAsset(data: Data([1, 2, 3]), mediaType: "image/png")]
      },
      output: Output.text()
    )

    _ = try await agent.generate(messages: [
      .init(
        role: .user,
        content: [
          .image(.init(data: .url(URL(string: "https://example.com/image.png")!)))
        ]
      )
    ])

    XCTAssertEqual(
      downloadsBox.get(),
      [
        DownloadRequest(
          url: URL(string: "https://example.com/image.png")!,
          isURLSupportedByModel: false
        )
      ]
    )
    XCTAssertNotNil(requestBox.get())
  }

  func testGenerate_messagesUsesProvidedMessages() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(generate: { request in
      requestBox.set(request)
      return Self.response()
    })

    let agent = Agent<Never, Output.Text>(
      model: model,
      output: Output.text()
    )

    let messages: [ModelMessage] = [
      .init(role: .user, content: [.text("Hello")]),
      .init(role: .assistant, content: [.text("Hi")])
    ]

    _ = try await agent.generate(messages: messages)

    XCTAssertEqual(requestBox.get()?.messages, messages)
  }

  func testStream_usesPrepareCall() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let agent = Agent<CallOptions, Output.Text>(
      model: model,
      toolChoice: .auto,
      output: Output.text(),
      prepareCall: { call in
        var updated = call
        updated.toolChoice = .none
        return updated
      }
    )

    let result = await agent.stream(prompt: "Hello, world!", options: .init(value: "test"))
    try await result.consumeStream()

    XCTAssertEqual(requestBox.get()?.toolChoice, .some(.none))
  }

  func testStream_prepareCallInjectsProviderOptions() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let agent = Agent<CallOptions, Output.Text>(
      model: model,
      output: Output.text(),
      prepareCall: { call in
        var updated = call
        updated.providerOptions = ["test": ["value": .string(call.options?.value ?? "missing")]]
        return updated
      }
    )

    let result = await agent.stream(prompt: "Hello, world!", options: .init(value: "test"))
    try await result.consumeStream()

    XCTAssertEqual(
      requestBox.get()?.providerOptions,
      ["test": ["value": .string("test")]]
    )
  }

  func testStream_messagesUsesProvidedMessages() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let agent = Agent<Never, Output.Text>(
      model: model,
      output: Output.text()
    )

    let messages: [ModelMessage] = [
      .init(role: .user, content: [.text("Hello")]),
      .init(role: .assistant, content: [.text("Hi")])
    ]

    let result = await agent.stream(messages: messages)
    try await result.consumeStream()

    XCTAssertEqual(requestBox.get()?.messages, messages)
  }

  func testStream_passesCancellationToken() async throws {
    let requestBox = RequestBox()
    let token = CancellationToken()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let agent = Agent<Never, Output.Text>(
      model: model,
      cancellationToken: token,
      output: Output.text()
    )

    let result = await agent.stream(prompt: "Hello, world!")
    try await result.consumeStream()

    XCTAssertTrue(requestBox.get()?.cancellationToken === token)
  }

  func testStream_instructionsString() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let agent = Agent<Never, Output.Text>(
      model: model,
      instructions: .text("INSTRUCTIONS"),
      output: Output.text()
    )

    let result = await agent.stream(prompt: "Hello, world!")
    try await result.consumeStream()

    XCTAssertEqual(
      requestBox.get()?.messages,
      [
        .system("INSTRUCTIONS"),
        .user("Hello, world!")
      ]
    )
  }

  func testStream_instructionsSystemMessage() async throws {
    let requestBox = RequestBox()
    let model = MockLanguageModel(
      generate: { _ in Self.response() },
      stream: { request in
        requestBox.set(request)
        return Self.makeStream([
          .streamStart(warnings: []),
          .responseMetadata(.init(id: "id-0", modelID: "mock-model", timestamp: Date(timeIntervalSince1970: 0))),
          .textStart(id: "1", providerMetadata: nil),
          .textDelta(id: "1", text: "Hello", providerMetadata: nil),
          .textEnd(id: "1", providerMetadata: nil),
          .finish(finishReason: .stop, usage: .init(), providerMetadata: nil)
        ])
      }
    )

    let systemMessage = ModelMessage(
      role: .system,
      content: [.text("INSTRUCTIONS")],
      providerOptions: ["test": ["value": .string("test")]]
    )

    let agent = Agent<Never, Output.Text>(
      model: model,
      instructions: .message(systemMessage),
      output: Output.text()
    )

    let result = await agent.stream(prompt: "Hello, world!")
    try await result.consumeStream()

    XCTAssertEqual(
      requestBox.get()?.messages,
      [
        systemMessage,
        .user("Hello, world!")
      ]
    )
  }
}
