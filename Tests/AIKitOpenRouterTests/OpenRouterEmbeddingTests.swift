import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterEmbeddingTests: XCTestCase {
  func testEmbedSingleValue() async throws {
    let response = JSONValue.object([
      "id": .string("test-id"),
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array(Array(repeating: .number(0.1), count: 3)),
          "index": .number(0),
        ]),
      ]),
      "model": .string("openai/text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(5),
        "total_tokens": .number(5),
        "cost": .number(0.00001),
      ]),
    ])

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/embeddings": .init(type: .jsonValue(response))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-key", transport: server.transport()))
    let model = provider.textEmbeddingModel("openai/text-embedding-3-small")
    let result = try await model.embed(.init(input: ["sunny day at the beach"]))

    XCTAssertEqual(result.vectors.count, 1)
    XCTAssertEqual(result.vectors[0].count, 3)
    XCTAssertEqual(result.usage?.inputTokens?.total, 5)
    if case let .object(meta)? = result.providerMetadata?["openrouter"],
       case let .object(usage)? = meta["usage"],
       case let .number(cost)? = usage["cost"] {
      XCTAssertEqual(cost, 0.00001)
    } else {
      XCTFail("Expected cost in provider metadata")
    }
  }
}
