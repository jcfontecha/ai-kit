import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterCompletionTests: XCTestCase {
  func testGenerateCompletion() async throws {
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .jsonValue(.object([
        "id": .string("cmpl-1"),
        "model": .string("openai/gpt-3.5-turbo-instruct"),
        "choices": .array([
          .object([
            "text": .string("Hello, World!"),
            "finish_reason": .string("stop"),
          ]),
        ]),
        "usage": .object([
          "prompt_tokens": .number(4),
          "completion_tokens": .number(3),
          "total_tokens": .number(7),
        ]),
      ])))
    ])

    let provider = createOpenRouter(.init(apiKey: "test", transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let response = try await model.generate(ModelRequest(messages: [ModelMessage.user("Hello")]))

    if case let .text(text, _) = response.content.first {
      XCTAssertEqual(text, "Hello, World!")
    } else {
      XCTFail("Expected text content")
    }
  }

  func testStreamCompletion() async throws {
    let chunks = [
      "data: {\"choices\":[{\"text\":\"Hello\",\"index\":0}]}\n\n",
      "data: {\"choices\":[{\"finish_reason\":\"stop\",\"index\":0}]}\n\n",
      "data: [DONE]\n\n",
    ]
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let stream = model.stream(ModelRequest(messages: [ModelMessage.user("Hello")]))

    let events = try await collectStream(stream)
    XCTAssertTrue(events.contains { part in
      if case let .textDelta(_, text, _) = part { return text == "Hello" }
      return false
    })
  }
}
