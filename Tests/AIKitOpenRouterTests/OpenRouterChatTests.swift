import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterChatTests: XCTestCase {
  func testGeneratePassesModelAndMessages() async throws {
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .jsonValue(.object([
        "id": .string("gen-123"),
        "model": .string("openai/gpt-3.5-turbo"),
        "choices": .array([
          .object([
            "message": .object([
              "role": .string("assistant"),
              "content": .string("Hello"),
            ]),
            "finish_reason": .string("stop"),
          ]),
        ]),
        "usage": .object([
          "prompt_tokens": .number(10),
          "completion_tokens": .number(5),
          "total_tokens": .number(15),
        ]),
      ])))
    ])

    let provider = createOpenRouter(.init(apiKey: "test", transport: server.transport()))
    let model = provider.chat("openai/gpt-3.5-turbo")

    _ = try await model.generate(ModelRequest(messages: [ModelMessage.user("Hello")]))

    let body = server.calls.first?.requestBodyJSON
    XCTAssertNotNil(body)
    if case let .object(object)? = body {
      XCTAssertEqual(object["model"], .string("openai/gpt-3.5-turbo"))
    } else {
      XCTFail("Expected object body")
    }
  }

  func testStreamTextDeltas() async throws {
    let chunks = [
      "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-3.5\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}\n\n",
      "data: {\"choices\":[{\"finish_reason\":\"stop\",\"index\":0}]}\n\n",
      "data: [DONE]\n\n",
    ]
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("openai/gpt-3.5-turbo")
    let stream = model.stream(ModelRequest(messages: [ModelMessage.user("Hello")]))

    let events = try await collectStream(stream)
    XCTAssertTrue(events.contains { part in
      if case let .textDelta(_, text, _) = part { return text == "Hello" }
      return false
    })
    XCTAssertTrue(events.contains { part in
      if case let .finish(finishReason, _, _) = part { return finishReason == .stop }
      return false
    })
  }
}
