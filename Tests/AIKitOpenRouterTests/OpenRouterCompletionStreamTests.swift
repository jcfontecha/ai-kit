import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterCompletionStreamTests: XCTestCase {
  private let testPrompt: [ModelMessage] = [.user("Hello")]

  private func streamChunks(
    content: [String],
    finishReason: String = "stop",
    usage: String
  ) -> [String] {
    var chunks: [String] = []
    for text in content {
      chunks.append(
        "data: {\"id\":\"cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT\",\"object\":\"text_completion\",\"created\":1711363440,\"choices\":[{\"text\":\"\(text)\",\"index\":0,\"logprobs\":null,\"finish_reason\":null}],\"model\":\"openai/gpt-3.5-turbo-instruct\"}\n\n"
      )
    }
    chunks.append(
      "data: {\"id\":\"cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H\",\"object\":\"text_completion\",\"created\":1711363310,\"choices\":[{\"text\":\"\",\"index\":0,\"logprobs\":null,\"finish_reason\":\"\(finishReason)\"}],\"model\":\"openai/gpt-3.5-turbo-instruct\"}\n\n"
    )
    chunks.append(
      "data: {\"id\":\"cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H\",\"object\":\"text_completion\",\"created\":1711363310,\"model\":\"openai/gpt-3.5-turbo-instruct\",\"usage\":\(usage),\"choices\":[]}\n\n"
    )
    chunks.append("data: [DONE]\n\n")
    return chunks
  }

  func testStreamTextDeltas() async throws {
    let chunks = streamChunks(
      content: ["Hello", ", ", "World!"],
      finishReason: "stop",
      usage: "{\"prompt_tokens\":10,\"total_tokens\":372,\"completion_tokens\":362}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")

    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let deltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(deltas, ["Hello", ", ", "World!", ""])

    guard let finish = parts.last, case let .finish(finishReason, usage, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .stop)
    XCTAssertEqual(usage.inputTokens?.total, 10)
    XCTAssertEqual(usage.outputTokens?.total, 362)

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"] {
      XCTAssertEqual(usageMeta["promptTokens"], .number(10))
      XCTAssertEqual(usageMeta["completionTokens"], .number(362))
      XCTAssertEqual(usageMeta["totalTokens"], .number(372))
    } else {
      XCTFail("Expected openrouter usage metadata")
    }
  }

  func testStreamIncludesUpstreamInferenceCostInFinishMetadata() async throws {
    let chunks = streamChunks(
      content: ["Hello"],
      usage: "{\"prompt_tokens\":5,\"total_tokens\":15,\"completion_tokens\":10,\"cost_details\":{\"upstream_inference_cost\":0.0036}}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"],
       case let .object(costDetails)? = usageMeta["costDetails"] {
      XCTAssertEqual(costDetails["upstreamInferenceCost"], .number(0.0036))
    } else {
      XCTFail("Expected upstreamInferenceCost in providerMetadata")
    }
  }

  func testStreamIncludesCostAndUpstreamInferenceCostInFinishMetadata() async throws {
    let chunks = streamChunks(
      content: ["Hello"],
      usage: "{\"prompt_tokens\":5,\"total_tokens\":15,\"completion_tokens\":10,\"cost\":0.0025,\"cost_details\":{\"upstream_inference_cost\":0.0036}}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"],
       case let .number(cost)? = usageMeta["cost"],
       case let .object(costDetails)? = usageMeta["costDetails"] {
      XCTAssertEqual(cost, 0.0025)
      XCTAssertEqual(costDetails["upstreamInferenceCost"], .number(0.0036))
    } else {
      XCTFail("Expected cost and upstreamInferenceCost in providerMetadata")
    }
  }

  func testStreamErrorPartsIncludeStructuredError() async throws {
    let chunks: [String] = [
      "data: {\"error\":{\"message\":\"The server had an error processing your request.\",\"type\":\"server_error\",\"param\":null,\"code\":null}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard parts.count >= 2 else { return XCTFail("Expected error and finish") }
    if case let .error(error) = parts[0] {
      XCTAssertEqual(error.message, "The server had an error processing your request.")
      XCTAssertEqual(error.type, "server_error")
      XCTAssertEqual(error.code, .null)
      XCTAssertEqual(error.param, .null)
    } else {
      XCTFail("Expected error part")
    }
    if case let .finish(finishReason, _, providerMetadata) = parts[1] {
      XCTAssertEqual(finishReason, .error)
      if case let .object(openrouter)? = providerMetadata?["openrouter"] {
        XCTAssertEqual(openrouter["usage"], .object([:]))
      } else {
        XCTFail("Expected empty usage metadata")
      }
    } else {
      XCTFail("Expected finish part")
    }
  }

  func testStreamUnparsableStreamPartsEmitErrorAndFinish() async throws {
    let chunks: [String] = [
      "data: {unparsable}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    XCTAssertEqual(parts.count, 2)
    if case .error = parts[0] {
      // message content is not stable; parity only requires an error part is emitted.
    } else {
      XCTFail("Expected error part")
    }
    if case let .finish(finishReason, _, providerMetadata) = parts[1] {
      XCTAssertEqual(finishReason, .error)
      if case let .object(openrouter)? = providerMetadata?["openrouter"] {
        XCTAssertEqual(openrouter["usage"], .object([:]))
      } else {
        XCTFail("Expected empty usage metadata")
      }
    } else {
      XCTFail("Expected finish part")
    }
  }

  func testStreamPassesModelPromptAndStreamOptions() async throws {
    let chunks = streamChunks(content: [], usage: "{\"prompt_tokens\":10,\"total_tokens\":372,\"completion_tokens\":362}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    _ = try await collectStream(model.stream(.init(messages: testPrompt)))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "stream": .bool(true),
        "stream_options": .object(["include_usage": .bool(true)]),
        "model": .string("openai/gpt-3.5-turbo-instruct"),
        "prompt": .string("Hello"),
      ])
    )
  }

  func testStreamPassesHeaders() async throws {
    let chunks = streamChunks(content: [], usage: "{\"prompt_tokens\":10,\"total_tokens\":372,\"completion_tokens\":362}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(
      apiKey: "test-api-key",
      headers: ["Custom-Provider-Header": "provider-header-value"],
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    _ = try await collectStream(model.stream(.init(
      messages: testPrompt,
      headers: ["Custom-Request-Header": "request-header-value"]
    )))

    XCTAssertEqual(
      server.calls.first?.requestHeaders,
      [
        "authorization": "Bearer test-api-key",
        "content-type": "application/json",
        "custom-provider-header": "provider-header-value",
        "custom-request-header": "request-header-value",
        "user-agent": "ai-sdk/openrouter/0.0.0-test",
      ]
    )
  }

  func testStreamPassesExtraBody() async throws {
    let chunks = streamChunks(content: [], usage: "{\"prompt_tokens\":10,\"total_tokens\":372,\"completion_tokens\":362}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(
      apiKey: "test-api-key",
      compatibility: .strict,
      transport: server.transport(),
      extraBody: [
        "custom_field": .string("custom_value"),
        "providers": .object([
          "openai": .object(["custom_field": .string("custom_value")]),
        ]),
      ]
    ))

    let model = provider.completion("openai/gpt-3.5-turbo-instruct")
    _ = try await collectStream(model.stream(.init(messages: testPrompt)))

    if case let .object(body)? = server.calls.first?.requestBodyJSON {
      XCTAssertEqual(body["custom_field"], .string("custom_value"))
      if case let .object(providers)? = body["providers"],
         case let .object(openai)? = providers["openai"] {
        XCTAssertEqual(openai["custom_field"], .string("custom_value"))
      } else {
        XCTFail("Expected providers.openai.custom_field")
      }
    } else {
      XCTFail("Expected request body object")
    }
  }
}
