import XCTest
@testable @_spi(Advanced) import AIKit
import AIKitProviders

final class PruneMessagesTests: XCTestCase {
  private func message(_ role: MessageRole, _ parts: [ModelMessagePart]) -> ModelMessage {
    ModelMessage(role: role, content: parts)
  }

  private func toolCall(id: String, name: String, input: String) -> ModelMessagePart {
    .toolCall(ToolCall(toolCallID: id, toolName: name, inputJSON: input))
  }

  private func toolResult(id: String, name: String, output: JSONValue) -> ModelMessagePart {
    .toolResult(ToolResult(toolCallID: id, toolName: name, output: output))
  }

  private var messagesFixture1: [ModelMessage] {
    [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-2")),
      ]),
      message(.tool, [
        .toolApprovalResponse(.init(approvalID: "approval-1", approved: true)),
        toolResult(
          id: "call-1",
          name: "get-weather-tool-1",
          output: .object(["type": .string("text"), "value": .string("sunny")])
        ),
        toolResult(
          id: "call-2",
          name: "get-weather-tool-2",
          output: .object(["type": .string("error-text"), "value": .string("Error: Fetching weather data failed")])
        ),
      ]),
      message(.assistant, [
        .reasoning("I have got the weather in Tokyo and Busan."),
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]
  }

  private var messagesFixture2: [ModelMessage] {
    [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-1")),
      ]),
    ]
  }

  private var multiTurnToolCallMessagesFixture: [ModelMessage] {
    [
      message(.user, [.text("ask me a question")]),
      message(.assistant, [
        .text("What can i help you with"),
        .toolCall(
          ToolCall(
            toolCallID: "toolu_01P9s4havAQSjDmS4eWT1N2V",
            toolName: "AskUserQuestion",
            inputJSON: "{\"question\":\"What would you like help with today?\",\"options\":[\"Tool 1 Option 1\",\"Tool 1 Option 2\",\"Tool 1 Option 3\"]}"
          )
        ),
      ]),
      message(.tool, [
        toolResult(
          id: "toolu_01P9s4havAQSjDmS4eWT1N2V",
          name: "AskUserQuestion",
          output: .object(["type": .string("text"), "value": .string("Something else")])
        ),
      ]),
      message(.assistant, [
        .toolCall(
          ToolCall(
            toolCallID: "toolu_01TMAuwWKLmBoQtx7K88dxsQ",
            toolName: "AskUserQuestion",
            inputJSON: "{\"question\":\"Ok what else?\",\"options\":[\"Tool 2 Option 1\",\"Tool 2 Option 2\",\"Tool 2 Option 3\"]}"
          )
        ),
      ]),
      message(.tool, [
        toolResult(
          id: "toolu_01TMAuwWKLmBoQtx7K88dxsQ",
          name: "AskUserQuestion",
          output: .object(["type": .string("text"), "value": .string("Other - I'll describe it")])
        ),
      ]),
      message(.assistant, [.text("What would you like to discuss or work on?")]),
      message(.user, [.text("never mind. lets end this conversation")]),
      message(.assistant, [.text("ok, have a nice day")]),
      message(.user, [.text("thank you")]),
    ]
  }

  func testPruneMessages_reasoning_all() {
    let result = pruneMessages(.init(messages: messagesFixture1, reasoning: .all))

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-2")),
      ]),
      message(.tool, [
        .toolApprovalResponse(.init(approvalID: "approval-1", approved: true)),
        toolResult(
          id: "call-1",
          name: "get-weather-tool-1",
          output: .object(["type": .string("text"), "value": .string("sunny")])
        ),
        toolResult(
          id: "call-2",
          name: "get-weather-tool-2",
          output: .object(["type": .string("error-text"), "value": .string("Error: Fetching weather data failed")])
        ),
      ]),
      message(.assistant, [
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_reasoning_beforeLastMessage() {
    let result = pruneMessages(.init(messages: messagesFixture1, reasoning: .beforeLastMessage))

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-2")),
      ]),
      message(.tool, [
        .toolApprovalResponse(.init(approvalID: "approval-1", approved: true)),
        toolResult(
          id: "call-1",
          name: "get-weather-tool-1",
          output: .object(["type": .string("text"), "value": .string("sunny")])
        ),
        toolResult(
          id: "call-2",
          name: "get-weather-tool-2",
          output: .object(["type": .string("error-text"), "value": .string("Error: Fetching weather data failed")])
        ),
      ]),
      message(.assistant, [
        .reasoning("I have got the weather in Tokyo and Busan."),
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_toolCalls_all() {
    let result = pruneMessages(.init(messages: messagesFixture1, toolCalls: .mode(.all)))

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
      ]),
      message(.assistant, [
        .reasoning("I have got the weather in Tokyo and Busan."),
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_toolCalls_beforeLastMessage() {
    let result = pruneMessages(.init(messages: messagesFixture2, toolCalls: .mode(.beforeLastMessage)))

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-1")),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_toolCalls_beforeLastMessage_multiTurnNoToolCallsAtEnd() {
    let result = pruneMessages(.init(messages: multiTurnToolCallMessagesFixture, toolCalls: .mode(.beforeLastMessage)))

    let expected: [ModelMessage] = [
      message(.user, [.text("ask me a question")]),
      message(.assistant, [.text("What can i help you with")]),
      message(.assistant, [.text("What would you like to discuss or work on?")]),
      message(.user, [.text("never mind. lets end this conversation")]),
      message(.assistant, [.text("ok, have a nice day")]),
      message(.user, [.text("thank you")]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_toolCalls_beforeLast2Messages() {
    let result = pruneMessages(.init(messages: messagesFixture1, toolCalls: .mode(.beforeLast2Messages)))

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
        toolCall(id: "call-1", name: "get-weather-tool-1", input: "{\"city\": \"Tokyo\"}"),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-2")),
      ]),
      message(.tool, [
        .toolApprovalResponse(.init(approvalID: "approval-1", approved: true)),
        toolResult(
          id: "call-1",
          name: "get-weather-tool-1",
          output: .object(["type": .string("text"), "value": .string("sunny")])
        ),
        toolResult(
          id: "call-2",
          name: "get-weather-tool-2",
          output: .object(["type": .string("error-text"), "value": .string("Error: Fetching weather data failed")])
        ),
      ]),
      message(.assistant, [
        .reasoning("I have got the weather in Tokyo and Busan."),
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }

  func testPruneMessages_twoToolSettings() {
    let result = pruneMessages(
      .init(
        messages: messagesFixture1,
        toolCalls: .settings([
          .init(mode: .all, tools: ["get-weather-tool-1"]),
          .init(mode: .beforeLast2Messages, tools: ["get-weather-tool-2"]),
        ])
      )
    )

    let expected: [ModelMessage] = [
      message(.user, [.text("Weather in Tokyo and Busan?")]),
      message(.assistant, [
        .reasoning("I need to get the weather in Tokyo and Busan."),
        toolCall(id: "call-2", name: "get-weather-tool-2", input: "{\"city\": \"Busan\"}"),
        .toolApprovalRequest(.init(approvalID: "approval-1", toolCallID: "call-2")),
      ]),
      message(.tool, [
        .toolApprovalResponse(.init(approvalID: "approval-1", approved: true)),
        toolResult(
          id: "call-2",
          name: "get-weather-tool-2",
          output: .object(["type": .string("error-text"), "value": .string("Error: Fetching weather data failed")])
        ),
      ]),
      message(.assistant, [
        .reasoning("I have got the weather in Tokyo and Busan."),
        .text("The weather in Tokyo is sunny. I could not get the weather in Busan."),
      ]),
    ]

    XCTAssertEqual(result, expected)
  }
}
