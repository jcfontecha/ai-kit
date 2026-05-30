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

  func testEmbedBatchInputReturnsMultipleVectors() async throws {
    let response = JSONValue.object([
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array([.number(0.1), .number(0.2)]),
          "index": .number(0),
        ]),
        .object([
          "object": .string("embedding"),
          "embedding": .array([.number(0.3), .number(0.4)]),
          "index": .number(1),
        ]),
      ]),
      "model": .string("text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(8),
        "total_tokens": .number(8),
      ]),
    ])

    let server = OpenAITestServer(config: [
      OpenAITestServer.embeddingsURL: .init(type: .jsonValue(response))
    ])

    let model = server.embeddingModel("text-embedding-3-small")
    let result = try await model.embed(.init(input: ["first", "second"]))

    XCTAssertEqual(result.vectors.count, 2)
    XCTAssertEqual(result.vectors[0], [0.1, 0.2])
    XCTAssertEqual(result.vectors[1], [0.3, 0.4])
    XCTAssertEqual(result.usage?.inputTokens?.total, 8)

    // The batch of values is forwarded as the `input` array.
    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected object body")
    }
    XCTAssertEqual(body["input"], .array([.string("first"), .string("second")]))
    XCTAssertEqual(body["model"], .string("text-embedding-3-small"))
  }

  func testEmbedOmitsUnsetSettings() async throws {
    let response = JSONValue.object([
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array([.number(0.5)]),
          "index": .number(0),
        ]),
      ]),
      "model": .string("text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(1),
        "total_tokens": .number(1),
      ]),
    ])

    let server = OpenAITestServer(config: [
      OpenAITestServer.embeddingsURL: .init(type: .jsonValue(response))
    ])

    let model = server.embeddingModel("text-embedding-3-small")
    _ = try await model.embed(.init(input: ["hello"]))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected object body")
    }
    XCTAssertNil(body["dimensions"])
    XCTAssertNil(body["encoding_format"])
    XCTAssertNil(body["user"])
  }

  func testEmbedPassesConfigHeaders() async throws {
    let response = JSONValue.object([
      "object": .string("list"),
      "data": .array([
        .object([
          "object": .string("embedding"),
          "embedding": .array([.number(0.1)]),
          "index": .number(0),
        ]),
      ]),
      "model": .string("text-embedding-3-small"),
      "usage": .object([
        "prompt_tokens": .number(1),
        "total_tokens": .number(1),
      ]),
    ])

    let server = OpenAITestServer(config: [
      OpenAITestServer.embeddingsURL: .init(type: .jsonValue(response))
    ])

    let model = server.embeddingModel("text-embedding-3-small")
    _ = try await model.embed(.init(input: ["hello"]))

    let headers = server.calls.first?.requestHeaders ?? [:]
    XCTAssertEqual(headers["authorization"], "Bearer test-api-key")
    XCTAssertEqual(headers["content-type"], "application/json")
  }
}
