import XCTest
@testable @_spi(Advanced) import AIKitCore
import AIKitProviders

final class AIUIMessageStreamClientTests: XCTestCase {
  func testValidateHeader_acceptsV1() throws {
    let response = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
    )!
    XCTAssertNoThrow(try AIUIMessageStreamClient.validateUIMessageStreamHeader(response))
  }

  func testValidateHeader_rejectsMissingOrInvalid() throws {
    let missing = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: [:]
    )!
    XCTAssertThrowsError(try AIUIMessageStreamClient.validateUIMessageStreamHeader(missing))

    let wrong = HTTPURLResponse(
      url: URL(string: "https://example.com")!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["x-vercel-ai-ui-message-stream": "v2"]
    )!
    XCTAssertThrowsError(try AIUIMessageStreamClient.validateUIMessageStreamHeader(wrong))
  }

  func testStreamTextStreamParts_usesTransportAndDecoder() async throws {
    let request = URLRequest(url: URL(string: "https://example.com")!)
    let chunks = [
      "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
      "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\n\n",
      "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let transport = TestTransport(
      response: HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: chunks
    )

    let client = AIUIMessageStreamClient(transport: transport)
    let parts = try await collectStream(try await client.streamParts(for: request))

    XCTAssertEqual(parts, [
      .textStart(id: "t1", providerMetadata: nil),
      .textDelta(id: "t1", delta: "Hello", providerMetadata: nil),
      .textEnd(id: "t1", providerMetadata: nil),
    ])
  }

  private struct TestTransport: HTTPTransport {
    let response: HTTPURLResponse
    let chunks: [String]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      (Data(), response)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
      let stream = AsyncThrowingStream(UInt8.self) { continuation in
        Task {
          for chunk in chunks {
            for b in chunk.utf8 {
              continuation.yield(b)
            }
          }
          continuation.finish()
        }
      }
      return (stream, response)
    }
  }

  private func collectStream<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var items: [T] = []
    for try await item in stream {
      items.append(item)
    }
    return items
  }
}
