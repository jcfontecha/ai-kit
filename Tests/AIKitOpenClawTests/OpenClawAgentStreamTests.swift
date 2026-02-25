import XCTest
@testable import AIKitOpenClaw
import AIKitProviders

final class OpenClawAgentStreamTests: XCTestCase {
  func testStreamRequiresTokenOrPassword() async {
    let ws = OpenClawTestWebSocket()
    let settings = OpenClawProviderSettings(
      gatewayURL: URL(string: "ws://example.invalid")!,
      token: nil,
      password: nil,
      sessionKey: "main",
      restoreVerboseLevelAfterRun: false,
      requestTimeoutSeconds: 1
    )

    let model = OpenClawAgentLanguageModel(
      id: "openclaw.agent",
      settings: settings,
      sessionKey: "main",
      agentId: nil,
      makeWebSocket: { _, _ in ws },
      makeRunID: { "run-1" }
    )

    do {
      _ = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
      XCTFail("Expected error")
    } catch {
      guard let gatewayError = error as? OpenClawGatewayError,
            case let .invalidConfiguration(message) = gatewayError
      else {
        return XCTFail("Unexpected error: \(error)")
      }
      XCTAssertTrue(message.contains("requires a token or password"))
    }
  }

  func testStreamSurfacesVerboseSetupTransportFailure() async {
    let ws = OpenClawTestWebSocket()

    await ws.setOnSend { text in
      let json = try? OpenClawJSON.decode(text)
      guard case let .object(obj) = json,
            obj["type"]?.stringValue == "req",
            let reqId = obj["id"]?.stringValue,
            let method = obj["method"]?.stringValue
      else { return }

      func push(_ value: JSONValue) async {
        let encoded = try! OpenClawJSON.encodeToString(value)
        await ws.pushIncoming(encoded)
      }

      if method == "connect" {
        await push(.object([
          "type": .string("event"),
          "event": .string("connect.challenge"),
          "payload": .object(["nonce": .string("nonce-1"), "ts": .number(0)]),
        ]))
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["type": .string("hello-ok"), "protocol": .number(3)]),
        ]))
        return
      }

      if method == "chat.history" {
        await ws.close()
      }
    }

    let settings = OpenClawProviderSettings(
      gatewayURL: URL(string: "ws://example.invalid")!,
      token: "token",
      sessionKey: "main",
      toolVerboseLevel: .full,
      restoreVerboseLevelAfterRun: false,
      requestTimeoutSeconds: 5
    )

    let model = OpenClawAgentLanguageModel(
      id: "openclaw.agent",
      settings: settings,
      sessionKey: "main",
      agentId: nil,
      makeWebSocket: { _, _ in ws },
      makeRunID: { "run-1" }
    )

    do {
      _ = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
      XCTFail("Expected transport error")
    } catch {
      if let gatewayError = error as? OpenClawGatewayError,
         case .disconnected = gatewayError {
        XCTFail("Expected underlying transport error, got disconnected")
      }
      XCTAssertTrue(error is OpenClawTestWebSocket.Closed, "Unexpected error type: \(error)")
    }
  }

  func testStreamEmitsTextDeltasAndToolEvents() async throws {
    let ws = OpenClawTestWebSocket()

    await ws.setOnSend { text in
      let json = try? OpenClawJSON.decode(text)
      guard case let .object(obj) = json,
            obj["type"]?.stringValue == "req",
            let reqId = obj["id"]?.stringValue,
            let method = obj["method"]?.stringValue
      else { return }

      func push(_ value: JSONValue) async {
        let encoded = try! OpenClawJSON.encodeToString(value)
        await ws.pushIncoming(encoded)
      }

      switch method {
      case "connect":
        await push(.object([
          "type": .string("event"),
          "event": .string("connect.challenge"),
          "payload": .object(["nonce": .string("nonce-1"), "ts": .number(0)]),
        ]))
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["type": .string("hello-ok"), "protocol": .number(3)]),
        ]))

      case "chat.history":
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["sessionKey": .string("main"), "verboseLevel": .string("off")]),
        ]))

      case "sessions.patch":
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["ok": .bool(true)]),
        ]))

      case "agent":
        let runId =
          obj["params"]?.objectValue?["idempotencyKey"]?.stringValue
          ?? "run-unknown"

        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
        ]))

        // Tool call start
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(1),
            "stream": .string("tool"),
            "ts": .number(0),
            "data": .object([
              "phase": .string("start"),
              "name": .string("read"),
              "toolCallId": .string("t1"),
              "args": .object(["path": .string("/tmp/foo.txt")]),
            ]),
          ]),
        ]))

        // Text deltas (cumulative)
        for (seq, text) in [(2, "H"), (3, "He"), (4, "Hello")] {
          await push(.object([
            "type": .string("event"),
            "event": .string("chat"),
            "payload": .object([
              "runId": .string(runId),
              "sessionKey": .string("main"),
              "seq": .number(Double(seq)),
              "state": .string("delta"),
              "message": .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                "timestamp": .number(0),
              ]),
            ]),
          ]))
        }

        // Tool update (preliminary)
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(5),
            "stream": .string("tool"),
            "ts": .number(0),
            "data": .object([
              "phase": .string("update"),
              "name": .string("read"),
              "toolCallId": .string("t1"),
              "partialResult": .object([
                "content": .array([.object(["type": .string("text"), "text": .string("partial")])]),
              ]),
            ]),
          ]),
        ]))

        // Tool result (final)
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(6),
            "stream": .string("tool"),
            "ts": .number(0),
            "data": .object([
              "phase": .string("result"),
              "name": .string("read"),
              "toolCallId": .string("t1"),
              "isError": .bool(false),
              "result": .object([
                "content": .array([.object(["type": .string("text"), "text": .string("final")])]),
              ]),
            ]),
          ]),
        ]))

        // Chat final
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(7),
            "state": .string("final"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("Hello")])]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))

        // Lifecycle end (finish trigger)
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(8),
            "stream": .string("lifecycle"),
            "ts": .number(0),
            "data": .object(["phase": .string("end")]),
          ]),
        ]))
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object([
            "runId": .string(runId),
            "status": .string("ok"),
            "summary": .string("completed"),
            "result": .object([
              "meta": .object([
                "stopReason": .string("stop"),
              ]),
            ]),
          ]),
        ]))

      default:
        return
      }
    }

    let settings = OpenClawProviderSettings(
      gatewayURL: URL(string: "ws://example.invalid")!,
      token: "token",
      sessionKey: "main",
      toolVerboseLevel: .full,
      restoreVerboseLevelAfterRun: false,
      requestTimeoutSeconds: 5
    )

    let model = OpenClawAgentLanguageModel(
      id: "openclaw.agent",
      settings: settings,
      sessionKey: "main",
      agentId: nil,
      makeWebSocket: { _, _ in ws },
      makeRequestID: {
        // Deterministic, but irrelevant since we always echo the request id back.
        UUID().uuidString
      },
      makeRunID: { "run-1" }
    )

    let parts = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))

    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["H", "e", "llo"])

    let toolCalls = parts.compactMap { part -> ToolCall? in
      guard case let .toolCall(call) = part else { return nil }
      return call
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls.first?.toolName, "read")
    XCTAssertEqual(toolCalls.first?.toolCallID, "t1")
    XCTAssertEqual(toolCalls.first?.providerExecuted, true)
    XCTAssertEqual(toolCalls.first?.dynamic, true)

    let toolResults = parts.compactMap { part -> ToolResult? in
      guard case let .toolResult(result) = part else { return nil }
      return result
    }
    XCTAssertEqual(toolResults.count, 2)
    XCTAssertEqual(toolResults.first?.preliminary, true)
    XCTAssertEqual(toolResults.last?.preliminary, false)
    XCTAssertEqual(toolResults.first?.dynamic, true)
    XCTAssertEqual(toolResults.last?.dynamic, true)

    guard let finish = parts.last, case let .finish(reason, _, metadata) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(reason, .stop)
    XCTAssertEqual(metadata?["openclaw"]?.objectValue?["sessionKey"], .string("main"))

    // Sanity: connect caps include tool-events.
    guard let connect = await ws.sentTexts.first,
          case let .object(connectObj) = try OpenClawJSON.decode(connect),
          connectObj["method"]?.stringValue == "connect"
    else {
      return XCTFail("Missing connect request")
    }
    let caps = connectObj["params"]?.objectValue?["caps"]?.arrayValue?.compactMap(\.stringValue) ?? []
    XCTAssertTrue(caps.contains("tool-events"))
  }

  private func collectStream<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var values: [T] = []
    for try await value in stream {
      values.append(value)
    }
    return values
  }
}
