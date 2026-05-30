import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAIEmbeddingModelTests: XCTestCase {
  func testEmbedSingleValue() async throws {
    let response = JSONValue.object([
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array(Array(repeating: .number(0.1), count: 3)),
          "index": .number(0),
        ]),
      ]),
      "model": .string("text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(5),
        "total_tokens": .number(5),
      ]),
    ])

    let server = OpenAITestServer(config: [
      OpenAITestServer.embeddingsURL: .init(type: .jsonValue(response))
    ])

    let model = server.embeddingModel("text-embedding-3-small")
    let result = try await model.embed(.init(input: ["sunny day at the beach"]))

    XCTAssertEqual(result.vectors.count, 1)
    XCTAssertEqual(result.vectors[0].count, 3)
    XCTAssertEqual(result.modelID, "text-embedding-3-small")
    XCTAssertEqual(result.usage?.inputTokens?.total, 5)
  }

  func testEmbedPassesOpenAISettings() async throws {
    let response = JSONValue.object([
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array(Array(repeating: .number(0.2), count: 4)),
          "index": .number(0),
        ]),
      ]),
      "model": .string("text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(3),
        "total_tokens": .number(3),
      ]),
    ])

    let server = OpenAITestServer(config: [
      OpenAITestServer.embeddingsURL: .init(type: .jsonValue(response))
    ])

    let model = server.embeddingModel(
      "text-embedding-3-small",
      settings: .init(dimensions: 4, encodingFormat: "float", user: "embed-user")
    )
    _ = try await model.embed(.init(input: ["hello"]))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected object body")
    }
    XCTAssertEqual(body["model"], .string("text-embedding-3-small"))
    XCTAssertEqual(body["input"], .array([.string("hello")]))
    XCTAssertEqual(body["dimensions"], .number(4))
    XCTAssertEqual(body["encoding_format"], .string("float"))
    XCTAssertEqual(body["user"], .string("embed-user"))
  }
}
