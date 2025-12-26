import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterStreamUsageAccountingTests: XCTestCase {
  private let testPrompt: [ModelMessage] = [.user("Hello")]

  private func makeChunks(includeUsage: Bool) -> [String] {
    var chunks: [String] = [
      "data: {\"id\":\"test-id\",\"model\":\"test-model\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}\n\n",
      "data: {\"choices\":[{\"finish_reason\":\"stop\",\"index\":0}]}\n\n",
    ]

    if includeUsage {
      chunks.append(
        "data: {\"usage\":{\"prompt_tokens\":10,\"prompt_tokens_details\":{\"cached_tokens\":5},\"completion_tokens\":20,\"completion_tokens_details\":{\"reasoning_tokens\":8},\"total_tokens\":30,\"cost\":0.0015,\"cost_details\":{\"upstream_inference_cost\":0.0019}},\"choices\":[]}\n\n"
      )
    }

    chunks.append("data: [DONE]\n\n")
    return chunks
  }

  func testIncludeStreamOptionsIncludeUsageInRequestWhenEnabled() async throws {
    let server = OpenRouterTestServer(config: [
      "https://api.openrouter.ai/chat/completions": .init(type: .streamChunks(makeChunks(includeUsage: true)))
    ])

    let provider = createOpenRouter(.init(
      baseURL: "https://api.openrouter.ai",
      apiKey: "test-api-key",
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.chat("test-model", settings: .init(usage: .init(include: true)))
    _ = try await collectStream(model.stream(.init(messages: testPrompt)))

    if case let .object(body)? = server.calls.first?.requestBodyJSON {
      XCTAssertEqual(body["stream"], .bool(true))
      XCTAssertEqual(body["stream_options"], .object(["include_usage": .bool(true)]))
    } else {
      XCTFail("Expected request body object")
    }
  }

  func testIncludeProviderMetadataInFinishWhenUsageChunkPresent() async throws {
    let server = OpenRouterTestServer(config: [
      "https://api.openrouter.ai/chat/completions": .init(type: .streamChunks(makeChunks(includeUsage: true)))
    ])

    let provider = createOpenRouter(.init(
      baseURL: "https://api.openrouter.ai",
      apiKey: "test-api-key",
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.chat("test-model", settings: .init(usage: .init(include: true)))
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"] {
      XCTAssertEqual(usageMeta["promptTokens"], .number(10))
      XCTAssertEqual(usageMeta["completionTokens"], .number(20))
      XCTAssertEqual(usageMeta["totalTokens"], .number(30))
      XCTAssertEqual(usageMeta["cost"], .number(0.0015))
      XCTAssertEqual(
        usageMeta["promptTokensDetails"],
        .object(["cachedTokens": .number(5)])
      )
      XCTAssertEqual(
        usageMeta["completionTokensDetails"],
        .object(["reasoningTokens": .number(8)])
      )
      XCTAssertEqual(
        usageMeta["costDetails"],
        .object(["upstreamInferenceCost": .number(0.0019)])
      )
    } else {
      XCTFail("Expected openrouter usage metadata")
    }
  }

  func testIncludeEmptyUsageMetadataWhenUsageChunkMissing() async throws {
    let server = OpenRouterTestServer(config: [
      "https://api.openrouter.ai/chat/completions": .init(type: .streamChunks(makeChunks(includeUsage: false)))
    ])

    let provider = createOpenRouter(.init(
      baseURL: "https://api.openrouter.ai",
      apiKey: "test-api-key",
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.chat("test-model")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    XCTAssertEqual(
      providerMetadata?["openrouter"],
      .object(["usage": .object([:])])
    )
  }
}

