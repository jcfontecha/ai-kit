import XCTest
@testable @_spi(Advanced) import AIKitCore
import AIKitProviders

final class ChatTransportWiringTests: XCTestCase {
  private struct TestTransport: ChatTransport {
    let parts: [AIUIMessageStreamPart]

    func sendMessages(
      _ options: ChatTransportSendMessagesOptions
    ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error> {
      AsyncThrowingStream(AIUIMessageStreamPart.self) { continuation in
        Task {
          for part in parts { continuation.yield(part) }
          continuation.finish()
        }
      }
    }

    func reconnectToStream(
      _ options: ChatTransportReconnectToStreamOptions
    ) async throws -> AsyncThrowingStream<AIUIMessageStreamPart, Error>? {
      nil
    }
  }

  func testChatSessionInit_transport_wiresRequestStream() async {
    let transport = TestTransport(parts: [
      .start(messageID: "msg-123", messageMetadata: nil),
      .startStep,
      .textStart(id: "t1"),
      .textDelta(id: "t1", delta: "Hello"),
      .textEnd(id: "t1"),
      .finishStep,
      .finish(finishReason: .stop),
    ])

    let session = ChatSession(.init(
      id: "chat-1",
      transport: transport,
      generateID: { "id-0" }
    ))

    await session.send(.init(role: .user, parts: [.text(.init(id: "u", text: "hi", state: .done))]))

    let messages = await session.messages
    XCTAssertEqual(messages.count, 2)
    XCTAssertEqual(messages[1].role, .assistant)
    let assistantText = messages[1].parts.compactMap { part -> String? in
      guard case let .text(t) = part else { return nil }
      return t.text
    }.joined()
    XCTAssertEqual(assistantText, "Hello")
  }
}
