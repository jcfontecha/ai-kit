import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class AIUIMessageEncodingTests: XCTestCase {
  func testEncode_textOnlyConversation() throws {
    let messages: [ChatMessage] = [
      .init(id: "u1", role: .user, parts: [.text(.init(id: "t-u1", text: "hi", state: .done))]),
      .init(id: "a1", role: .assistant, parts: [
        .stepStart,
        .text(.init(id: "t-a1", text: "hello", state: .done)),
      ]),
    ]

    let uiMessages = try AIUIMessageEncoder().encode(messages)
    let json = try encodeToJSONValue(uiMessages)

    let expected = JSONValue.array([
      JSONValue.object([
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
      .object([
        "id": .string("a1"),
        "role": .string("assistant"),
        "parts": .array([
          .object(["type": .string("step-start")]),
          .object([
            "type": .string("text"),
            "text": .string("hello"),
            "state": .string("done"),
          ]),
        ]),
      ]),
    ])
    XCTAssertEqual(json, expected)
  }

  func testEncode_dynamicTool_invocationStates() throws {
    let toolCallID = "tool-1"
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .tool(.init(
          toolCallID: toolCallID,
          toolName: "getLocation",
          title: "Get Location",
          providerExecuted: false,
          dynamic: true,
          input: .object(["city": .string("NYC")]),
          rawInput: nil,
          output: nil,
          callProviderMetadata: .init(["x": .string("y")]),
          state: .approvalRequested(approvalID: "approval-1")
        )),
      ]),
    ]

    let uiMessages = try AIUIMessageEncoder().encode(messages)
    let json = try encodeToJSONValue(uiMessages)

    let expected = JSONValue.array([
      .object([
        "id": .string("a1"),
        "role": .string("assistant"),
        "parts": .array([
          .object([
            "type": .string("dynamic-tool"),
            "toolName": .string("getLocation"),
            "toolCallId": .string(toolCallID),
            "title": .string("Get Location"),
            "providerExecuted": .bool(false),
            "state": .string("approval-requested"),
            "input": .object(["city": .string("NYC")]),
            "callProviderMetadata": .object(["x": .string("y")]),
            "approval": .object(["id": .string("approval-1")]),
          ]),
        ]),
      ]),
    ])
    XCTAssertEqual(json, expected)
  }

  func testEncode_dynamicTool_outputDenied_includesApprovalIDAndApprovedFalse() throws {
    let messages: [ChatMessage] = [
      .init(id: "a1", role: .assistant, parts: [
        .tool(.init(
          toolCallID: "call-1",
          toolName: "tool1",
          title: nil,
          providerExecuted: false,
          dynamic: true,
          input: .object(["value": .string("value")]),
          rawInput: nil,
          output: nil,
          callProviderMetadata: nil,
          state: .outputDenied(approvalID: "approval-1", reason: "nope")
        )),
      ]),
    ]

    let uiMessages = try AIUIMessageEncoder().encode(messages)
    let json = try encodeToJSONValue(uiMessages)

    let expected = JSONValue.array([
      .object([
        "id": .string("a1"),
        "role": .string("assistant"),
        "parts": .array([
          .object([
            "type": .string("dynamic-tool"),
            "toolName": .string("tool1"),
            "toolCallId": .string("call-1"),
            "providerExecuted": .bool(false),
            "state": .string("output-denied"),
            "input": .object(["value": .string("value")]),
            "approval": .object([
              "id": .string("approval-1"),
              "approved": .bool(false),
              "reason": .string("nope"),
            ]),
          ]),
        ]),
      ]),
    ])

    XCTAssertEqual(json, expected)
  }

  private func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    guard let json = JSONValue.from(object) else {
      XCTFail("Could not convert encoded JSON to JSONValue")
      return .null
    }
    return json
  }
}
