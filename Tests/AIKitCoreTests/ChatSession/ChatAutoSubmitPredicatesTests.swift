import XCTest
@testable @_spi(Advanced) import AIKitCore
import AIKitProviders

final class ChatAutoSubmitPredicatesTests: XCTestCase {
  func testLastAssistantMessageIsCompleteWithToolCalls_false_ifLastStepOnlyHasText() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_location_123",
          toolName: "getLocation",
          input: .object([:]),
          output: .string("New York"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .text(.init(id: "t1", text: "The current weather in New York is windy.", state: .done)),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_whenTextAfterLastToolResultInLastStep() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_regular_123",
          toolName: "getWeatherInformation",
          input: .object(["city": .string("New York")]),
          output: .string("windy"),
          state: .outputAvailable(preliminary: false)
        )),
        .text(.init(id: "t1", text: "The current weather in New York is windy.", state: .done)),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_whenToolHasOutputErrorState() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_regular_123",
          toolName: "getWeatherInformation",
          input: .object(["city": .string("New York")]),
          output: nil,
          state: .outputError(errorText: "Unable to get weather information")
        )),
        .text(.init(id: "t1", text: "The current weather in New York is windy.", state: .done)),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_whenDynamicToolCallIsComplete() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: .string("sunny"),
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_false_whenDynamicToolCallIsStillStreamingInput() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: nil,
          state: .inputStreaming
        )),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_false_whenDynamicToolCallHasInputButNoOutput() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: nil,
          state: .inputAvailable
        )),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_whenDynamicToolCallHasError() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: nil,
          state: .outputError(errorText: "Failed to fetch weather data")
        )),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_whenMixingRegularAndDynamicAndAllComplete() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_regular_123",
          toolName: "getWeatherInformation",
          input: .object(["city": .string("New York")]),
          output: .string("windy"),
          state: .outputAvailable(preliminary: false)
        )),
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: .string("sunny"),
          state: .outputAvailable(preliminary: false)
        )),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_false_whenMixingRegularAndDynamicAndSomeIncomplete() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_regular_123",
          toolName: "getWeatherInformation",
          input: .object(["city": .string("New York")]),
          output: .string("windy"),
          state: .outputAvailable(preliminary: false)
        )),
        .tool(.init(
          toolCallID: "call_dynamic_123",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("San Francisco")]),
          output: nil,
          state: .inputAvailable
        )),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_true_forMultiStepWhereLastStepHasCompleteDynamicToolCalls() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_location_123",
          toolName: "getLocation",
          input: .object([:]),
          output: .string("New York"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_456",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("New York")]),
          output: .string("cloudy"),
          state: .outputAvailable(preliminary: false)
        )),
        .text(.init(id: "t1", text: "The current weather in New York is cloudy.", state: .done)),
      ]),
    ]

    XCTAssertTrue(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_false_forMultiStepWhereLastStepHasIncompleteDynamicToolCalls() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "call_location_123",
          toolName: "getLocation",
          input: .object([:]),
          output: .string("New York"),
          state: .outputAvailable(preliminary: false)
        )),
        .stepStart,
        .tool(.init(
          toolCallID: "call_dynamic_456",
          toolName: "getDynamicWeather",
          providerExecuted: false,
          dynamic: true,
          input: .object(["location": .string("New York")]),
          output: nil,
          state: .inputStreaming
        )),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }

  func testLastAssistantMessageIsCompleteWithToolCalls_false_forCompleteProviderExecutedToolCalls() {
    let messages: [ChatMessage] = [
      .init(id: "1", role: .assistant, parts: [
        .stepStart,
        .tool(.init(
          toolCallID: "srvtoolu_01KSMqkKSbgKhCwGZHQDaV48",
          toolName: "web_search",
          providerExecuted: true,
          dynamic: false,
          input: .object(["query": .string("New York weather")]),
          output: .array([]),
          state: .outputAvailable(preliminary: false)
        )),
        .text(.init(id: "t1", text: "The current weather in New York is windy.", state: .done)),
      ]),
    ]

    XCTAssertFalse(ChatAutoSubmitPredicates.lastAssistantMessageIsCompleteWithToolCalls(messages: messages))
  }
}
