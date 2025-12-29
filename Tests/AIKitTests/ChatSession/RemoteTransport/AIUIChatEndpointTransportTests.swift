import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class AIUIChatEndpointTransportTests: XCTestCase {
  func testHeaders_transportHeadersAreIncluded_byDefault_andAddsAIKitUserAgentSuffix() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      headers: ["X-Test-Header": "test-value"],
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: [
        .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
      ],
      trigger: .submitMessage,
      messageID: "m123",
      options: nil
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-test-header"), "test-value")

    guard let userAgent = request.value(forHTTPHeaderField: "User-Agent") else {
      return XCTFail("Expected User-Agent header")
    }
    XCTAssertTrue(userAgent.contains("aikit/"))
  }

  func testHeaders_transportHeadersFunctionIsEvaluated() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      headers: {
        ["X-Test-Header": "test-value-fn"]
      },
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: [
        .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
      ],
      trigger: .submitMessage,
      messageID: "m123",
      options: nil
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-test-header"), "test-value-fn")
  }

  func testBody_transportBodyIsIncluded_inRequestBodyByDefault() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      body: .object(["someData": .bool(true)]),
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: [
        .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
      ],
      trigger: .submitMessage,
      messageID: "m123",
      options: nil
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    let bodyJSON = try decodeBodyJSONValue(request)
    guard case let .object(obj) = bodyJSON else { return XCTFail("Expected object") }
    XCTAssertEqual(obj["someData"], .bool(true))
  }

  func testBody_transportBodyFunctionIsEvaluated() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      body: {
        .object(["someData": .bool(true)])
      },
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: [
        .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
      ],
      trigger: .submitMessage,
      messageID: "m123",
      options: nil
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    let bodyJSON = try decodeBodyJSONValue(request)
    guard case let .object(obj) = bodyJSON else { return XCTFail("Expected object") }
    XCTAssertEqual(obj["someData"], .bool(true))
  }

  func testReconnectToStream_includesTransportHeaders_andAddsAIKitUserAgentSuffix() async throws {
    let baseURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: baseURL,
        statusCode: 204,
        httpVersion: nil,
        headerFields: [:]
      )!,
      chunks: []
    )

    let endpoint = AIUIChatEndpointTransport(
      url: baseURL,
      httpTransport: transport,
      headers: ["X-Test-Header": "test-value"],
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.reconnectToStream(chatID: "chat-1", options: nil)
    XCTAssertNil(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-test-header"), "test-value")

    guard let userAgent = request.value(forHTTPHeaderField: "User-Agent") else {
      return XCTFail("Expected User-Agent header")
    }
    XCTAssertTrue(userAgent.contains("aikit/"))
  }

  func testRequestBody_includesIDMessagesAndMergesOptionsBody() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
    ]

    let options = ChatRequestOptions(body: .object(["sessionId": .string("s1")]))
    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: messages,
      trigger: .submitMessage,
      messageID: "m123",
      options: options
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.url, requestURL)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let bodyJSON = try decodeBodyJSONValue(request)
    XCTAssertEqual(bodyJSON, .object([
      "id": .string("chat-1"),
      "messages": .array([
        .object([
          "id": .string("u1"),
          "role": .string("user"),
          "parts": .array([
            .object([
              "type": .string("text"),
              "text": .string("hi"),
              "state": .string("done"),
            ]),
          ]),
        ]),
      ]),
      "trigger": .string("submit-message"),
      "messageId": .string("m123"),
      "sessionId": .string("s1"),
    ]))
  }

  func testMetadata_doesNotAppearInRequestBodyByDefault() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
    ]

    let options = ChatRequestOptions(
      body: .object(["sessionId": .string("s1")]),
      metadata: .object(["traceId": .string("trace-123")])
    )

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: messages,
      trigger: .submitMessage,
      messageID: "m123",
      options: options
    )
    _ = try await collectStream(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    let bodyJSON = try decodeBodyJSONValue(request)

    XCTAssertEqual(bodyJSON, .object([
      "id": .string("chat-1"),
      "messages": .array([
        .object([
          "id": .string("u1"),
          "role": .string("user"),
          "parts": .array([
            .object([
              "type": .string("text"),
              "text": .string("hi"),
              "state": .string("done"),
            ]),
          ]),
        ]),
      ]),
      "trigger": .string("submit-message"),
      "messageId": .string("m123"),
      "sessionId": .string("s1"),
    ]))
  }

  func testPrepareSendMessagesRequest_receivesMetadata_andCanOverrideHeaders() async throws {
    let requestURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: requestURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    actor Capture {
      var metadata: JSONValue?

      func record(_ value: JSONValue?) {
        metadata = value
      }
    }
    let capture = Capture()

    let endpoint = AIUIChatEndpointTransport(
      url: requestURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport),
      prepareSendMessagesRequest: { options in
        await capture.record(options.requestMetadata)
        guard case let .object(obj)? = options.requestMetadata else { return nil }
        guard case let .string(traceID)? = obj["traceId"] else { return nil }
        return .init(headers: ["x-trace-id": traceID])
      }
    )

    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
    ]

    let stream = try await endpoint.requestStream(
      chatID: "chat-1",
      messages: messages,
      trigger: .submitMessage,
      messageID: "m123",
      options: .init(metadata: .object(["traceId": .string("trace-123")]))
    )
    _ = try await collectStream(stream)

    let captured = await capture.metadata
    XCTAssertEqual(captured, .object(["traceId": .string("trace-123")]))

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-trace-id"), "trace-123")
  }

  func testReconnectToStream_204ReturnsNil_andUsesDefaultURL() async throws {
    let baseURL = URL(string: "https://example.com/api/chat")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: baseURL,
        statusCode: 204,
        httpVersion: nil,
        headerFields: [:]
      )!,
      chunks: []
    )

    let endpoint = AIUIChatEndpointTransport(
      url: baseURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    let stream = try await endpoint.reconnectToStream(
      chatID: "chat-1",
      options: .init(headers: ["x-client": "ios"])
    )

    XCTAssertNil(stream)

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url, URL(string: "https://example.com/api/chat/chat-1/stream")!)
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-client"), "ios")
  }

  func testPrepareReconnectToStreamRequest_receivesMetadata_andCanOverrideURLAndHeaders() async throws {
    let baseURL = URL(string: "https://example.com/api/chat")!
    let overrideURL = URL(string: "https://example.com/custom/stream")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: overrideURL,
        statusCode: 204,
        httpVersion: nil,
        headerFields: [:]
      )!,
      chunks: []
    )

    actor Capture {
      var metadata: JSONValue?

      func record(_ value: JSONValue?) { metadata = value }
    }
    let capture = Capture()

    let endpoint = AIUIChatEndpointTransport(
      url: baseURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport),
      prepareReconnectToStreamRequest: { options in
        await capture.record(options.requestMetadata)
        return .init(url: overrideURL, headers: ["x-resume": "1"])
      }
    )

    let stream = try await endpoint.reconnectToStream(
      chatID: "chat-1",
      options: .init(metadata: .object(["traceId": .string("trace-123")]))
    )
    XCTAssertNil(stream)

    let captured = await capture.metadata
    XCTAssertEqual(captured, .object(["traceId": .string("trace-123")]))

    guard let request = transport.lastRequest else { return XCTFail("Expected request") }
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.url, overrideURL)
    XCTAssertEqual(request.value(forHTTPHeaderField: "x-resume"), "1")
  }

  func testReconnectToStream_200ReturnsStreamParts() async throws {
    let baseURL = URL(string: "https://example.com/api/chat")!
    let resumeURL = URL(string: "https://example.com/api/chat/chat-1/stream")!

    let transport = RecordingTransport(
      response: HTTPURLResponse(
        url: resumeURL,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["x-vercel-ai-ui-message-stream": "v1"]
      )!,
      chunks: [
        "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
        "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\n\n",
        "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
        "data: [DONE]\n\n",
      ]
    )

    let endpoint = AIUIChatEndpointTransport(
      url: baseURL,
      httpTransport: transport,
      encoder: .init(),
      streamClient: .init(transport: transport)
    )

    guard let stream = try await endpoint.reconnectToStream(chatID: "chat-1", options: nil) else {
      return XCTFail("Expected a stream")
    }

    let parts = try await collectStream(stream)
    XCTAssertEqual(parts, [
      .textStart(id: "t1", providerMetadata: nil),
      .textDelta(id: "t1", delta: "Hello", providerMetadata: nil),
      .textEnd(id: "t1", providerMetadata: nil),
    ])
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

  private func collectStream<T: Sendable>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var items: [T] = []
    for try await item in stream {
      items.append(item)
    }
    return items
  }
}
