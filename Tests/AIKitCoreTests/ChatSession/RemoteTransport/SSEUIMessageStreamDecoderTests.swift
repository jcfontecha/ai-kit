import XCTest
@testable @_spi(Advanced) import AIKitCore
import AIKitProviders

final class SSEUIMessageStreamDecoderTests: XCTestCase {
  func testDecode_textStreamingAndFinish() async throws {
    let chunks = [
      "data: {\"type\":\"start-step\"}\r\n\r\n",
      "data: {\"type\":\"text-start\",\"id\":\"t1\"}\r\n\r\n",
      "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\r\n\r\n",
      "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\" world\"}\r\n\r\n",
      "data: {\"type\":\"text-end\",\"id\":\"t1\"}\r\n\r\n",
      "data: {\"type\":\"finish-step\",\"finishReason\":\"stop\"}\r\n\r\n",
      "data: {\"type\":\"finish\",\"finishReason\":\"stop\",\"usage\":{\"inputTokens\":{\"total\":1},\"outputTokens\":{\"total\":2}}}\r\n\r\n",
      "data: [DONE]\r\n\r\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))
    XCTAssertEqual(parts, [
      .startStep,
      .textStart(id: "t1", providerMetadata: nil),
      .textDelta(id: "t1", delta: "Hello", providerMetadata: nil),
      .textDelta(id: "t1", delta: " world", providerMetadata: nil),
      .textEnd(id: "t1", providerMetadata: nil),
      .finishStep,
      .finish(finishReason: .stop, messageMetadata: nil),
    ])
  }

  func testDecode_toolInputAvailable_mapsToToolInputAvailableAndToolOutputAvailable() async throws {
    let chunks = [
      "data: {\"type\":\"tool-input-start\",\"toolCallId\":\"tc1\",\"toolName\":\"getLocation\"}\n\n",
      "data: {\"type\":\"tool-input-delta\",\"toolCallId\":\"tc1\",\"inputTextDelta\":\"{\\\"city\\\":\\\"NYC\\\"\"}\n\n",
      "data: {\"type\":\"tool-input-delta\",\"toolCallId\":\"tc1\",\"inputTextDelta\":\"}\"}\n\n",
      "data: {\"type\":\"tool-input-available\",\"toolCallId\":\"tc1\",\"toolName\":\"getLocation\",\"input\":{\"city\":\"NYC\"}}\n\n",
      "data: {\"type\":\"tool-output-available\",\"toolCallId\":\"tc1\",\"toolName\":\"getLocation\",\"output\":{\"lat\":1,\"lng\":2}}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))

    XCTAssertEqual(parts.count, 5)
    XCTAssertEqual(parts[0], .toolInputStart(.init(toolCallID: "tc1", toolName: "getLocation")))
    XCTAssertEqual(parts[1], .toolInputDelta(.init(toolCallID: "tc1", inputTextDelta: "{\"city\":\"NYC\"")))
    XCTAssertEqual(parts[2], .toolInputDelta(.init(toolCallID: "tc1", inputTextDelta: "}")))

    guard case let .toolInputAvailable(call) = parts[3] else { return XCTFail("Expected toolInputAvailable") }
    XCTAssertEqual(call.toolCallID, "tc1")
    XCTAssertEqual(call.toolName, "getLocation")
    XCTAssertEqual(call.input, .object(["city": .string("NYC")]))

    guard case let .toolOutputAvailable(result) = parts[4] else { return XCTFail("Expected toolOutputAvailable") }
    XCTAssertEqual(result.toolCallID, "tc1")
    XCTAssertEqual(result.output, .object(["lat": .number(1), "lng": .number(2)]))
  }

  func testDecode_reasoningParts_includeProviderMetadata() async throws {
    let chunks = [
      "data: {\"type\":\"reasoning-start\",\"id\":\"r1\"}\n\n",
      "data: {\"type\":\"reasoning-delta\",\"id\":\"r1\",\"delta\":\"Hello\",\"providerMetadata\":{\"testProvider\":{\"signature\":\"123\"}}}\n\n",
      "data: {\"type\":\"reasoning-end\",\"id\":\"r1\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))

    XCTAssertEqual(parts.count, 3)
    XCTAssertEqual(parts[0], .reasoningStart(id: "r1", providerMetadata: nil))

    let metadata: ProviderMetadata = ["testProvider": .object(["signature": .string("123")])]
    XCTAssertEqual(parts[1], .reasoningDelta(id: "r1", delta: "Hello", providerMetadata: metadata))
    XCTAssertEqual(parts[2], .reasoningEnd(id: "r1", providerMetadata: nil))
  }

  func testDecode_fileSourceURLAndSourceDocument() async throws {
    let chunks = [
      "data: {\"type\":\"file\",\"url\":\"data:text/plain;base64,SGVsbG8=\",\"mediaType\":\"text/plain\"}\n\n",
      "data: {\"type\":\"source-url\",\"sourceId\":\"s1\",\"url\":\"https://example.com\",\"title\":\"Example\",\"providerMetadata\":{\"testProvider\":{\"signature\":\"123\"}}}\n\n",
      "data: {\"type\":\"source-document\",\"sourceId\":\"s2\",\"mediaType\":\"application/pdf\",\"title\":\"Doc\",\"filename\":\"doc.pdf\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))

    let providerMetadata: ProviderMetadata = ["testProvider": .object(["signature": .string("123")])]
    XCTAssertEqual(parts, [
      .file(.init(url: "data:text/plain;base64,SGVsbG8=", mediaType: "text/plain", providerMetadata: nil)),
      .sourceURL(.init(sourceID: "s1", url: "https://example.com", title: "Example", providerMetadata: providerMetadata)),
      .sourceDocument(.init(sourceID: "s2", mediaType: "application/pdf", title: "Doc", filename: "doc.pdf", providerMetadata: nil)),
    ])
  }

  func testDecode_toolInputErrorAndToolOutputError() async throws {
    let chunks = [
      "data: {\"type\":\"tool-input-start\",\"toolCallId\":\"call-1\",\"toolName\":\"cityAttractions\"}\n\n",
      "data: {\"type\":\"tool-input-delta\",\"toolCallId\":\"call-1\",\"inputTextDelta\":\"{\\\"cities\\\":\\\"San Francisco\\\"\"}\n\n",
      "data: {\"type\":\"tool-input-error\",\"toolCallId\":\"call-1\",\"toolName\":\"cityAttractions\",\"input\":\"{ \\\"cities\\\": \\\"San Francisco\\\" }\",\"errorText\":\"Invalid input for tool cityAttractions\"}\n\n",
      "data: {\"type\":\"tool-output-error\",\"toolCallId\":\"call-1\",\"errorText\":\"Invalid input for tool cityAttractions\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))

    XCTAssertEqual(parts.count, 4)
    XCTAssertEqual(parts[0], .toolInputStart(.init(toolCallID: "call-1", toolName: "cityAttractions")))
    XCTAssertEqual(parts[1], .toolInputDelta(.init(toolCallID: "call-1", inputTextDelta: "{\"cities\":\"San Francisco\"")))

    guard case let .toolInputError(inputError) = parts[2] else { return XCTFail("Expected toolInputError") }
    XCTAssertEqual(inputError.toolCallID, "call-1")
    XCTAssertEqual(inputError.toolName, "cityAttractions")
    XCTAssertEqual(inputError.input, .string("{ \"cities\": \"San Francisco\" }"))
    XCTAssertEqual(inputError.errorText, "Invalid input for tool cityAttractions")

    guard case let .toolOutputError(outputError) = parts[3] else { return XCTFail("Expected toolOutputError") }
    XCTAssertEqual(outputError.toolCallID, "call-1")
    XCTAssertEqual(outputError.errorText, "Invalid input for tool cityAttractions")
  }

  func testDecode_dataPart_yieldsDataStreamPart() async throws {
    let chunks = [
      "data: {\"type\":\"data-ai-kit\",\"id\":\"d1\",\"data\":{\"traceId\":\"t\"},\"transient\":true}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))
    XCTAssertEqual(parts, [
      .data(.init(type: "data-ai-kit", id: "d1", data: .object(["traceId": .string("t")]), transient: true)),
    ])
  }

  func testDecode_unknownType_yieldsRawJSON() async throws {
    let chunks = [
      "data: {\"type\":\"new-thing\",\"hello\":\"world\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let parts = try await collectStream(SSEUIMessageStreamDecoder().decode(byteStream(chunks)))
    XCTAssertEqual(parts, [.raw(.object(["type": .string("new-thing"), "hello": .string("world")]))])
  }

  func testChatSession_requestStream_runsWithoutModel() async {
    let chunks = [
      "data: {\"type\":\"start-step\"}\n\n",
      "data: {\"type\":\"text-start\",\"id\":\"t1\"}\n\n",
      "data: {\"type\":\"text-delta\",\"id\":\"t1\",\"delta\":\"Hello\"}\n\n",
      "data: {\"type\":\"text-end\",\"id\":\"t1\"}\n\n",
      "data: {\"type\":\"finish-step\",\"finishReason\":\"stop\"}\n\n",
      "data: {\"type\":\"finish\",\"finishReason\":\"stop\"}\n\n",
      "data: [DONE]\n\n",
    ]

    let decoder = SSEUIMessageStreamDecoder()
    let stream = byteStream(chunks)
    let session = ChatSession(.init(
      model: nil,
      requestStream: { _, _, _, _, _, _ in decoder.decode(stream) },
      generateID: { "id-0" }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[0].role, .user)
    XCTAssertEqual(messages[1].role, .assistant)

    let assistantText = messages[1].parts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(assistantText, "Hello")

    let status = await session.status
    XCTAssertEqual(status, .ready)
  }

  private func byteStream(_ chunks: [String]) -> AsyncThrowingStream<UInt8, Error> {
    AsyncThrowingStream( UInt8.self) { continuation in
      Task {
        for chunk in chunks {
          for b in chunk.utf8 {
            continuation.yield(b)
          }
        }
        continuation.finish()
      }
    }
  }

  private func collectStream<T: Sendable>(
    _ stream: AsyncThrowingStream<T, Error>
  ) async throws -> [T] {
    var items: [T] = []
    for try await item in stream {
      items.append(item)
    }
    return items
  }
}
