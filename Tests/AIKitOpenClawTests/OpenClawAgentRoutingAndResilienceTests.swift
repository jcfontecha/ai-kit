import XCTest
@testable import AIKitOpenClaw
import AIKitProviders

final class OpenClawAgentRoutingAndResilienceTests: XCTestCase {
  func testStreamIgnoresIntermediateLifecycleEndAndContinuesDeltas() async throws {
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
        let runId = obj["params"]?.objectValue?["idempotencyKey"]?.stringValue ?? "run-unknown"
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
        ]))
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(1),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("H")])]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(2),
            "stream": .string("lifecycle"),
            "ts": .number(0),
            "data": .object(["phase": .string("end")]),
          ]),
        ]))
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(3),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("He")])]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(4),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("Hello")])]),
              "timestamp": .number(0),
            ]),
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
      makeRunID: { "run-1" }
    )

    let parts = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["H", "e", "llo"])
  }

  func testStreamEmitsPendingToolCallsFromFinalOutcomeWhenToolEventsMissing() async throws {
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
        let runId = obj["params"]?.objectValue?["idempotencyKey"]?.stringValue ?? "run-unknown"
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
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
                "stopReason": .string("tool_calls"),
                "pendingToolCalls": .array([
                  .object([
                    "id": .string("call_1"),
                    "name": .string("get_weather"),
                    "arguments": .string("{\"city\":\"sf\"}"),
                  ]),
                  .object([
                    "id": .string("call_2"),
                    "name": .string("get_time"),
                    "arguments": .string("{\"zone\":\"utc\"}"),
                  ]),
                ]),
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
      makeRunID: { "run-1" }
    )

    let parts = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
    let toolCalls = parts.compactMap { part -> ToolCall? in
      guard case let .toolCall(call) = part else { return nil }
      return call
    }
    XCTAssertEqual(toolCalls.map(\.toolCallID), ["call_1", "call_2"])
    XCTAssertEqual(toolCalls.map(\.toolName), ["get_weather", "get_time"])

    guard let finish = parts.last, case let .finish(reason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(reason, .toolCalls)
  }

  func testStreamEmitsAssistantTextFromFinalOutcomeWhenEventsMissing() async throws {
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
        let runId = obj["params"]?.objectValue?["idempotencyKey"]?.stringValue ?? "run-unknown"
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
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
              "payloads": .array([
                .object([
                  "text": .string("Recovered final text"),
                ]),
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
      makeRunID: { "run-1" }
    )

    let parts = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["Recovered final text"])

    guard let finish = parts.last, case let .finish(reason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(reason, .stop)
  }

  func testStreamPrefersAgentAssistantEventsAndAvoidsChatResetDuplication() async throws {
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
        let runId = obj["params"]?.objectValue?["idempotencyKey"]?.stringValue ?? "run-unknown"
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
        ]))

        // First assistant segment.
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(1),
            "stream": .string("assistant"),
            "ts": .number(0),
            "data": .object([
              "text": .string("Sure, let me do both!"),
              "delta": .string("Sure, let me do both!"),
            ]),
          ]),
        ]))
        // Matching chat payload (should be ignored when assistant agent stream exists).
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(2),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("Sure, let me do both!")])]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))

        // Second assistant segment after a tool loop.
        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(3),
            "stream": .string("assistant"),
            "ts": .number(0),
            "data": .object([
              "text": .string("There"),
              "delta": .string("There"),
            ]),
          ]),
        ]))
        // Matching chat payload (also ignored).
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(4),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([.object(["type": .string("text"), "text": .string("There")])]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))

        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(5),
            "stream": .string("assistant"),
            "ts": .number(0),
            "data": .object([
              "text": .string("There you go — one bash command and one file read."),
              "delta": .string(" you go — one bash command and one file read."),
            ]),
          ]),
        ]))
        await push(.object([
          "type": .string("event"),
          "event": .string("chat"),
          "payload": .object([
            "runId": .string(runId),
            "sessionKey": .string("main"),
            "seq": .number(6),
            "state": .string("delta"),
            "message": .object([
              "role": .string("assistant"),
              "content": .array([
                .object([
                  "type": .string("text"),
                  "text": .string("There you go — one bash command and one file read."),
                ]),
              ]),
              "timestamp": .number(0),
            ]),
          ]),
        ]))

        await push(.object([
          "type": .string("event"),
          "event": .string("agent"),
          "payload": .object([
            "runId": .string(runId),
            "seq": .number(7),
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
      makeRunID: { "run-1" }
    )

    let parts = try await collectStream(model.stream(.init(messages: [.user("Hello")], toolChoice: .none)))
    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }

    XCTAssertEqual(
      textDeltas,
      [
        "Sure, let me do both!",
        " There",
        " you go — one bash command and one file read.",
      ]
    )
  }

  func testStreamAppliesOpenClawRoutingOverridesFromProviderOptions() async throws {
    let ws = OpenClawTestWebSocket()
    actor CaptureBox {
      var sessionKey: String?
      var agentId: String?

      func set(sessionKey: String?, agentId: String?) {
        self.sessionKey = sessionKey
        self.agentId = agentId
      }

      func snapshot() -> (sessionKey: String?, agentId: String?) {
        (sessionKey, agentId)
      }
    }
    let capture = CaptureBox()

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
        let params = obj["params"]?.objectValue ?? [:]
        await capture.set(
          sessionKey: params["sessionKey"]?.stringValue,
          agentId: params["agentId"]?.stringValue
        )
        let runId = params["idempotencyKey"]?.stringValue ?? "run-unknown"
        await push(.object([
          "type": .string("res"),
          "id": .string(reqId),
          "ok": .bool(true),
          "payload": .object(["runId": .string(runId), "status": .string("accepted")]),
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
              "meta": .object(["stopReason": .string("stop")]),
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
      agentId: "main",
      toolVerboseLevel: .full,
      restoreVerboseLevelAfterRun: false,
      requestTimeoutSeconds: 5
    )
    let model = OpenClawAgentLanguageModel(
      id: "openclaw.agent",
      settings: settings,
      sessionKey: "main",
      agentId: "main",
      makeWebSocket: { _, _ in ws },
      makeRunID: { "run-1" }
    )

    let request = ModelRequest(
      messages: [.user("Hello")],
      toolChoice: .none,
      providerOptions: [
        "openclaw": [
          "sessionKey": .string("agent:main:workspace"),
          "agentId": .string("beta"),
          "conversationId": .string("Team Alpha"),
          "threadId": .string("Sprint 42"),
        ],
      ]
    )
    let parts = try await collectStream(model.stream(request))
    let captured = await capture.snapshot()

    XCTAssertEqual(captured.agentId, "beta")
    XCTAssertEqual(
      captured.sessionKey,
      "agent:main:workspace:conversation:team-alpha:thread:sprint-42"
    )
    guard let finish = parts.last, case let .finish(_, _, metadata) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(
      metadata?["openclaw"]?.objectValue?["sessionKey"],
      .string("agent:main:workspace:conversation:team-alpha:thread:sprint-42")
    )
    XCTAssertEqual(metadata?["openclaw"]?.objectValue?["agentId"], .string("beta"))
    XCTAssertEqual(metadata?["openclaw"]?.objectValue?["conversationId"], .string("Team Alpha"))
    XCTAssertEqual(metadata?["openclaw"]?.objectValue?["threadId"], .string("Sprint 42"))
  }

  private func collectStream<T>(_ stream: AsyncThrowingStream<T, Error>) async throws -> [T] {
    var values: [T] = []
    for try await value in stream {
      values.append(value)
    }
    return values
  }
}
