import XCTest
@testable import AIKitCore
import AIKitProviders

final class ChatSessionRemoteEndpointIntegrationTests: XCTestCase {
  func testChatSession_usesEndpointTransportAndUpdatesTranscript() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!
    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"start-step\"}\n\n",
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"finish-step\",\"finishReason\":\"stop\"}\n\n",
        "data: {\"type\":\"finish\",\"finishReason\":\"stop\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(url: requestURL, httpTransport: transport)

    let session = ChatSession(.init(
      id: "chat-1",
      model: nil,
      requestStream: endpoint.makeRequestStream(),
      generateID: { "id-0" }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    let body = try decodeBodyJSONValue(request)

    guard case let .object(obj) = body else { return XCTFail("Expected object body") }
    XCTAssertEqual(obj["id"], .string("chat-1"))
    XCTAssertNotNil(obj["messages"])
    XCTAssertEqual(obj["trigger"], .string("submit-message"))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0].role, .user)
    XCTAssertEqual(messages[1].role, .assistant)

    let assistantText = messages[1].parts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(assistantText, "Hello")
  }

  private final class RecordingTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    let response: HTTPURLResponse
    let chunks: [String]

    init(response: HTTPURLResponse, chunks: [String]) {
      self.response = response
      self.chunks = chunks
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
      lastRequest = request
      return (Data(), response)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, HTTPURLResponse) {
      lastRequest = request
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

  private func decodeBodyJSONValue(_ request: URLRequest) throws -> JSONValue {
    guard let body = request.httpBody else {
      XCTFail("Expected httpBody")
      return .null
    }
    let obj = try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
    guard let json = JSONValue.from(obj) else {
      XCTFail("Could not convert request JSON to JSONValue")
      return .null
    }
    return json
  }
}
