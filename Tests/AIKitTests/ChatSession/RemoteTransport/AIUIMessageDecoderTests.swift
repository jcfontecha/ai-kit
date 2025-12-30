import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class AIUIMessageDecoderTests: XCTestCase {
  private struct ValidationError: Error, Equatable {}

  func testDecode_basicMessagesAndParts() async throws {
    let ui: [AIUIMessage] = [
      .init(
        id: "m1",
        role: "user",
        metadata: .object(["meta": .string("v")]),
        parts: [
          .object(["type": .string("text"), "text": .string("Hello")]),
          .object(["type": .string("file"), "mediaType": .string("text/plain"), "url": .string("https://example.com/file.txt")]),
          .object(["type": .string("data-test"), "id": .string("d1"), "data": .object(["k": .string("v")])]),
        ]
      ),
      .init(
        id: "m2",
        role: "assistant",
        metadata: nil,
        parts: [
          .object(["type": .string("step-start")]),
          .object(["type": .string("text"), "text": .string("Hi")]),
          .object([
            "type": .string("tool-weather"),
            "toolCallId": .string("call-1"),
            "state": .string("output-available"),
            "input": .object(["city": .string("London")]),
            "output": .object(["weather": .string("sunny")]),
          ]),
          .object([
            "type": .string("source-url"),
            "sourceId": .string("s1"),
            "url": .string("https://example.com"),
            "title": .string("Example"),
          ]),
          .object([
            "type": .string("source-document"),
            "sourceId": .string("s2"),
            "mediaType": .string("application/pdf"),
            "title": .string("Doc"),
            "filename": .string("doc.pdf"),
          ]),
        ]
      ),
    ]

    let decoded = try await AIUIMessageDecoder().decode(ui)
    XCTAssertEqual(decoded.count, 2)

    XCTAssertEqual(decoded[0].id, "m1")
    XCTAssertEqual(decoded[0].role, .user)
    XCTAssertEqual(decoded[0].metadata, .object(["meta": .string("v")]))
    XCTAssertEqual(decoded[0].parts.count, 3)

    guard case let .text(t0) = decoded[0].parts[0] else { return XCTFail("expected text part") }
    XCTAssertEqual(t0.text, "Hello")
    XCTAssertEqual(t0.state, .done)

    guard case let .file(f0) = decoded[0].parts[1] else { return XCTFail("expected file part") }
    XCTAssertEqual(f0.mediaType, "text/plain")
    guard case let .url(url) = f0.data else { return XCTFail("expected url file data") }
    XCTAssertEqual(url.absoluteString, "https://example.com/file.txt")

    guard case let .data(d0) = decoded[0].parts[2] else { return XCTFail("expected data part") }
    XCTAssertEqual(d0.type, "data-test")
    XCTAssertEqual(d0.id, "d1")
    XCTAssertEqual(d0.data, .object(["k": .string("v")]))

    XCTAssertEqual(decoded[1].id, "m2")
    XCTAssertEqual(decoded[1].role, .assistant)
    XCTAssertEqual(decoded[1].parts.count, 5)

    XCTAssertEqual(decoded[1].parts[0], .stepStart)

    guard case let .tool(tool) = decoded[1].parts[2] else { return XCTFail("expected tool part") }
    XCTAssertEqual(tool.toolCallID, "call-1")
    XCTAssertEqual(tool.toolName, "weather")
    XCTAssertEqual(tool.state, .outputAvailable(preliminary: false))
    XCTAssertEqual(tool.input, .object(["city": .string("London")]))
    XCTAssertEqual(tool.output, .object(["weather": .string("sunny")]))
  }

  func testDecode_validatesMessageMetadata_whenValidatorProvided() async throws {
    let ui: [AIUIMessage] = [
      .init(id: "m1", role: "user", metadata: .number(1), parts: [.object(["type": .string("text"), "text": .string("hi")])]),
    ]

    do {
      _ = try await AIUIMessageDecoder().decode(ui, validateMessageMetadata: { metadata in
        guard case .object? = metadata else { throw ValidationError() }
      })
      XCTFail("expected throw")
    } catch let error as ValidationError {
      XCTAssertEqual(error, ValidationError())
    }
  }

  func testDecode_validatesDataParts_whenValidatorProvided() async throws {
    let ui: [AIUIMessage] = [
      .init(
        id: "m1",
        role: "assistant",
        metadata: nil,
        parts: [
          .object(["type": .string("data-test"), "data": .object(["k": .string("v")])]),
        ]
      ),
    ]

    do {
      _ = try await AIUIMessageDecoder().decode(ui, validateDataParts: [
        "data-test": { value in
          guard case .string = value else { throw ValidationError() }
        },
      ])
      XCTFail("expected throw")
    } catch let error as ValidationError {
      XCTAssertEqual(error, ValidationError())
    }
  }

  func testDecode_toolApprovalStates_requireApprovalID() async throws {
    let ui: [AIUIMessage] = [
      .init(
        id: "m1",
        role: "assistant",
        metadata: nil,
        parts: [
          .object([
            "type": .string("tool-weather"),
            "toolCallId": .string("call-1"),
            "state": .string("approval-requested"),
            "input": .object(["city": .string("London")]),
          ]),
        ]
      ),
    ]

    do {
      _ = try await AIUIMessageDecoder().decode(ui)
      XCTFail("expected throw")
    } catch let error as AIUIMessageDecodingError {
      XCTAssertEqual(error, .missingApprovalID(toolCallID: "call-1", state: "approval-requested"))
    }
  }
}
