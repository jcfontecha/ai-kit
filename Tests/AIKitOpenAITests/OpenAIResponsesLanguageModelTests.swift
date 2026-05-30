import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAIResponsesLanguageModelTests: XCTestCase {
  private var testPrompt: [ModelMessage] {
    [.user("Hello")]
  }

  private func makeServer(_ response: OpenAITestServer.ResponseConfig) -> OpenAITestServer {
    OpenAITestServer(config: [OpenAITestServer.responsesURL: response])
  }

  private func textResponse(
    text: String,
    status: String = "completed",
    usage: JSONValue = .object([
      "input_tokens": .number(17),
      "output_tokens": .number(8),
      "total_tokens": .number(25),
    ])
  ) -> JSONValue {
    .object([
      "id": .string("resp_123"),
      "object": .string("response"),
      "model": .string("gpt-4o-2024-08-06"),
      "status": .string(status),
      "output": .array([
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string(text)])
          ]),
        ])
      ]),
      "usage": usage,
    ])
  }

  // MARK: - Non-streaming generate

  func testGenerateText() async throws {
    let server = makeServer(.init(type: .jsonValue(textResponse(text: "Hello, World!"))))
    let model = server.responsesModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [.text("Hello, World!")])
    XCTAssertEqual(result.finishReason, .stop)
    XCTAssertEqual(result.usage.inputTokens?.total, 17)
    XCTAssertEqual(result.usage.outputTokens?.total, 8)
    XCTAssertEqual(result.response.id, "resp_123")
  }

  func testGenerateFunctionCall() async throws {
    let response = JSONValue.object([
      "id": .string("resp_tool"),
      "object": .string("response"),
      "model": .string("gpt-4o-2024-08-06"),
      "status": .string("completed"),
      "output": .array([
        .object([
          "type": .string("function_call"),
          "id": .string("fc_1"),
          "call_id": .string("call_abc"),
          "name": .string("get_weather"),
          "arguments": .string("{\"location\":\"SF\"}"),
        ])
      ]),
      "usage": .object([
        "input_tokens": .number(20),
        "output_tokens": .number(10),
        "total_tokens": .number(30),
      ]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.finishReason, .toolCalls)
    XCTAssertEqual(result.content.count, 1)
    guard case let .toolCall(call) = result.content.first else {
      return XCTFail("Expected tool call")
    }
    XCTAssertEqual(call.toolCallID, "call_abc")
    XCTAssertEqual(call.toolName, "get_weather")
    XCTAssertEqual(call.inputJSON, "{\"location\":\"SF\"}")
    XCTAssertEqual(call.input, .object(["location": .string("SF")]))
  }

  func testGenerateReasoningAndText() async throws {
    let response = JSONValue.object([
      "id": .string("resp_r"),
      "object": .string("response"),
      "model": .string("gpt-5"),
      "status": .string("completed"),
      "output": .array([
        .object([
          "type": .string("reasoning"),
          "summary": .array([
            .object(["type": .string("summary_text"), "text": .string("Thinking...")])
          ]),
        ]),
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string("Answer")])
          ]),
        ]),
      ]),
      "usage": .object([
        "input_tokens": .number(5),
        "output_tokens": .number(5),
        "output_tokens_details": .object(["reasoning_tokens": .number(3)]),
      ]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-5")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [.reasoning("Thinking..."), .text("Answer")])
    XCTAssertEqual(result.usage.outputTokens?.reasoning, 3)
  }

  func testExtractCachedAndReasoningUsage() async throws {
    let response = JSONValue.object([
      "id": .string("resp_u"),
      "object": .string("response"),
      "model": .string("gpt-5"),
      "status": .string("completed"),
      "output": .array([
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string("Hi")])
          ]),
        ])
      ]),
      "usage": .object([
        "input_tokens": .number(20),
        "output_tokens": .number(30),
        "total_tokens": .number(50),
        "input_tokens_details": .object(["cached_tokens": .number(8)]),
        "output_tokens_details": .object(["reasoning_tokens": .number(12)]),
      ]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-5")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.usage.inputTokens?.total, 20)
    XCTAssertEqual(result.usage.inputTokens?.cacheRead, 8)
    XCTAssertEqual(result.usage.outputTokens?.total, 30)
    XCTAssertEqual(result.usage.outputTokens?.reasoning, 12)
    XCTAssertEqual(result.response.id, "resp_u")
  }

  func testReasoningEmptySummaryProducesNoReasoning() async throws {
    let response = JSONValue.object([
      "id": .string("resp_es"),
      "object": .string("response"),
      "model": .string("gpt-5"),
      "status": .string("completed"),
      "output": .array([
        .object([
          "type": .string("reasoning"),
          "summary": .array([]),
        ]),
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string("Answer")])
          ]),
        ]),
      ]),
      "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-5")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [.text("Answer")])
  }

  func testMultipleReasoningBlocks() async throws {
    let response = JSONValue.object([
      "id": .string("resp_mr"),
      "object": .string("response"),
      "model": .string("gpt-5"),
      "status": .string("completed"),
      "output": .array([
        .object([
          "type": .string("reasoning"),
          "summary": .array([
            .object(["type": .string("summary_text"), "text": .string("First thought.")])
          ]),
        ]),
        .object([
          "type": .string("reasoning"),
          "summary": .array([
            .object(["type": .string("summary_text"), "text": .string("Second thought.")])
          ]),
        ]),
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string("Done")])
          ]),
        ]),
      ]),
      "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-5")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [
      .reasoning("First thought."),
      .reasoning("Second thought."),
      .text("Done"),
    ])
  }

  func testStopFinishReason() async throws {
    let server = makeServer(.init(type: .jsonValue(textResponse(text: "Hi", status: "completed"))))
    let model = server.responsesModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))
    XCTAssertEqual(result.finishReason, .stop)
  }

  func testContentFilterFinishReason() async throws {
    let response = JSONValue.object([
      "id": .string("resp_cf"),
      "object": .string("response"),
      "model": .string("gpt-4o"),
      "status": .string("incomplete"),
      "incomplete_details": .object(["reason": .string("content_filter")]),
      "output": .array([]),
      "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))
    XCTAssertEqual(result.finishReason, .contentFilter)
  }

  func testIncompleteMaxTokensFinishReason() async throws {
    let response = JSONValue.object([
      "id": .string("resp_i"),
      "object": .string("response"),
      "model": .string("gpt-4o"),
      "status": .string("incomplete"),
      "incomplete_details": .object(["reason": .string("max_output_tokens")]),
      "output": .array([
        .object([
          "type": .string("message"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("output_text"), "text": .string("partial")])
          ]),
        ])
      ]),
      "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
    ])
    let server = makeServer(.init(type: .jsonValue(response)))
    let model = server.responsesModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.finishReason, .length)
  }

  func testErrorStatusThrows() async throws {
    let server = makeServer(.init(
      type: .error(.object([
        "error": .object([
          "message": .string("Invalid request"),
          "type": .string("invalid_request_error"),
        ])
      ])),
      status: 400
    ))
    let model = server.responsesModel("gpt-4o")
    do {
      _ = try await model.generate(.init(messages: testPrompt))
      XCTFail("Expected error")
    } catch let error as OpenAIAPIError {
      XCTAssertEqual(error.statusCode, 400)
      XCTAssertTrue(error.message.contains("Invalid request"))
    }
  }

  // MARK: - Input item conversion

  func testRequestBodyShape() async throws {
    let server = makeServer(.init(type: .jsonValue(textResponse(text: "ok"))))
    let model = server.responsesModel("gpt-4o")

    let messages: [ModelMessage] = [
      .system("You are helpful"),
      .user("What is the weather?"),
      .init(role: .assistant, content: [
        .text(.init(text: "Let me check")),
        .toolCall(.init(toolCallID: "call_1", toolName: "get_weather", inputJSON: "{\"city\":\"SF\"}")),
      ]),
      .init(role: .tool, content: [
        .toolResult(.init(toolCallID: "call_1", toolName: "get_weather", output: .object(["temp": .number(70)]))),
      ]),
    ]

    let tools = [
      ToolDefinition(
        name: "get_weather",
        description: "Get the weather",
        inputSchema: .init(["type": .string("object"), "properties": .object([:])])
      )
    ]

    _ = try await model.generate(.init(messages: messages, tools: tools))

    let call = server.urls[OpenAITestServer.responsesURL]?.calls.first
    guard case let .object(body)? = call?.requestBodyJSON else {
      return XCTFail("Missing request body")
    }

    XCTAssertEqual(body["model"], .string("gpt-4o"))
    XCTAssertEqual(body["instructions"], .string("You are helpful"))

    guard case let .array(input)? = body["input"] else {
      return XCTFail("Missing input array")
    }
    // system goes to instructions, so input has: user, assistant message, function_call, function_call_output
    XCTAssertEqual(input.count, 4)

    XCTAssertEqual(input[0], .object([
      "type": .string("message"),
      "role": .string("user"),
      "content": .array([
        .object(["type": .string("input_text"), "text": .string("What is the weather?")])
      ]),
    ]))

    XCTAssertEqual(input[1], .object([
      "type": .string("message"),
      "role": .string("assistant"),
      "content": .array([
        .object(["type": .string("output_text"), "text": .string("Let me check")])
      ]),
    ]))

    XCTAssertEqual(input[2], .object([
      "type": .string("function_call"),
      "call_id": .string("call_1"),
      "name": .string("get_weather"),
      "arguments": .string("{\"city\":\"SF\"}"),
    ]))

    XCTAssertEqual(input[3], .object([
      "type": .string("function_call_output"),
      "call_id": .string("call_1"),
      "output": .string("{\"temp\":70}"),
    ]))

    // Tools are flattened (function fields at top level, not nested under "function").
    guard case let .array(toolsValue)? = body["tools"], case let .object(tool) = toolsValue.first else {
      return XCTFail("Missing tools")
    }
    XCTAssertEqual(tool["type"], .string("function"))
    XCTAssertEqual(tool["name"], .string("get_weather"))
    XCTAssertEqual(tool["description"], .string("Get the weather"))
    XCTAssertNotNil(tool["parameters"])
  }

  func testPassProviderOptions() async throws {
    let server = makeServer(.init(type: .jsonValue(textResponse(text: "ok"))))
    let model = server.responsesModel(
      "gpt-5",
      options: .init(
        include: ["reasoning.encrypted_content"],
        instructions: "Be concise",
        metadata: ["key": "value"],
        parallelToolCalls: false,
        previousResponseID: "resp_prev",
        promptCacheKey: "pck",
        reasoningEffort: .high,
        reasoningSummary: "auto",
        serviceTier: .flex,
        store: false,
        textVerbosity: .low,
        truncation: .auto,
        user: "user-id"
      )
    )
    _ = try await model.generate(.init(messages: testPrompt))

    guard case let .object(body)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected object body")
    }
    XCTAssertEqual(body["instructions"], .string("Be concise"))
    XCTAssertEqual(body["previous_response_id"], .string("resp_prev"))
    XCTAssertEqual(body["store"], .bool(false))
    XCTAssertEqual(body["truncation"], .string("auto"))
    XCTAssertEqual(body["include"], .array([.string("reasoning.encrypted_content")]))
    XCTAssertEqual(body["metadata"], .object(["key": .string("value")]))
    XCTAssertEqual(body["service_tier"], .string("flex"))
    XCTAssertEqual(body["prompt_cache_key"], .string("pck"))
    XCTAssertEqual(body["parallel_tool_calls"], .bool(false))
    XCTAssertEqual(body["user"], .string("user-id"))
    XCTAssertEqual(body["reasoning"], .object([
      "effort": .string("high"),
      "summary": .string("auto"),
    ]))
    XCTAssertEqual(body["text"], .object(["verbosity": .string("low")]))
  }

  // MARK: - Streaming

  func testStreamTextDeltas() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_s\",\"model\":\"gpt-4o-2024-08-06\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\"}}\n\n",
      "data: {\"type\":\"response.content_part.added\",\"output_index\":0,\"item_id\":\"msg_1\",\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\n",
      "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"item_id\":\"msg_1\",\"delta\":\"Hello\"}\n\n",
      "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"item_id\":\"msg_1\",\"delta\":\", World!\"}\n\n",
      "data: {\"type\":\"response.output_text.done\",\"output_index\":0,\"item_id\":\"msg_1\",\"text\":\"Hello, World!\"}\n\n",
      "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_s\",\"status\":\"completed\",\"usage\":{\"input_tokens\":17,\"output_tokens\":5,\"total_tokens\":22}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["Hello", ", World!"])

    XCTAssertTrue(parts.contains { if case .textStart = $0 { return true }; return false })
    XCTAssertTrue(parts.contains { if case .textEnd = $0 { return true }; return false })

    guard let finish = parts.last, case let .finish(finishReason, usage, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .stop)
    XCTAssertEqual(usage.inputTokens?.total, 17)
    XCTAssertEqual(usage.outputTokens?.total, 5)
  }

  func testStreamReasoningDelta() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_r\",\"model\":\"gpt-5\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"id\":\"rs_1\"}}\n\n",
      "data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"item_id\":\"rs_1\",\"delta\":\"Think \"}\n\n",
      "data: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":0,\"item_id\":\"rs_1\",\"delta\":\"hard\"}\n\n",
      "data: {\"type\":\"response.reasoning_summary_text.done\",\"output_index\":0,\"item_id\":\"rs_1\",\"text\":\"Think hard\"}\n\n",
      "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_r\",\"status\":\"completed\",\"usage\":{\"input_tokens\":3,\"output_tokens\":3}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-5")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let reasoningDeltas = parts.compactMap { part -> String? in
      guard case let .reasoningDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(reasoningDeltas, ["Think ", "hard"])
    XCTAssertTrue(parts.contains { if case .reasoningStart = $0 { return true }; return false })
    XCTAssertTrue(parts.contains { if case .reasoningEnd = $0 { return true }; return false })
  }

  func testStreamFunctionCall() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_f\",\"model\":\"gpt-4o-2024-08-06\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_abc\",\"name\":\"get_weather\",\"arguments\":\"\"}}\n\n",
      "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"item_id\":\"fc_1\",\"delta\":\"{\\\"location\\\":\"}\n\n",
      "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"item_id\":\"fc_1\",\"delta\":\"\\\"SF\\\"}\"}\n\n",
      "data: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0,\"item_id\":\"fc_1\",\"arguments\":\"{\\\"location\\\":\\\"SF\\\"}\"}\n\n",
      "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_abc\",\"name\":\"get_weather\",\"arguments\":\"{\\\"location\\\":\\\"SF\\\"}\"}}\n\n",
      "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_f\",\"status\":\"completed\",\"usage\":{\"input_tokens\":17,\"output_tokens\":10}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let toolInputStarts = parts.compactMap { part -> String? in
      guard case let .toolInputStart(_, toolName, _, _, _, _) = part else { return nil }
      return toolName
    }
    XCTAssertEqual(toolInputStarts, ["get_weather"])

    let toolInputDeltas = parts.compactMap { part -> String? in
      guard case let .toolInputDelta(_, delta, _) = part else { return nil }
      return delta
    }
    XCTAssertEqual(toolInputDeltas, ["{\"location\":", "\"SF\"}"])

    XCTAssertTrue(parts.contains { if case .toolInputEnd = $0 { return true }; return false })

    let toolCalls = parts.compactMap { part -> ToolCall? in
      guard case let .toolCall(call) = part else { return nil }
      return call
    }
    XCTAssertEqual(toolCalls.count, 1)
    XCTAssertEqual(toolCalls.first?.toolCallID, "call_abc")
    XCTAssertEqual(toolCalls.first?.toolName, "get_weather")
    XCTAssertEqual(toolCalls.first?.inputJSON, "{\"location\":\"SF\"}")

    guard let finish = parts.last, case let .finish(finishReason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .toolCalls)
  }

  func testStreamReasoningUsageOnCompleted() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_uc\",\"model\":\"gpt-5\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\"}}\n\n",
      "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"item_id\":\"msg_1\",\"delta\":\"Hi\"}\n\n",
      "data: {\"type\":\"response.output_text.done\",\"output_index\":0,\"item_id\":\"msg_1\",\"text\":\"Hi\"}\n\n",
      "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_uc\",\"status\":\"completed\",\"usage\":{\"input_tokens\":20,\"output_tokens\":30,\"total_tokens\":50,\"input_tokens_details\":{\"cached_tokens\":8},\"output_tokens_details\":{\"reasoning_tokens\":12}}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-5")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(finishReason, usage, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .stop)
    XCTAssertEqual(usage.inputTokens?.total, 20)
    XCTAssertEqual(usage.inputTokens?.cacheRead, 8)
    XCTAssertEqual(usage.outputTokens?.total, 30)
    XCTAssertEqual(usage.outputTokens?.reasoning, 12)
  }

  func testStreamIncompleteFinishReason() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_inc\",\"model\":\"gpt-4o\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"item_id\":\"msg_1\",\"delta\":\"partial\"}\n\n",
      "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"resp_inc\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(finishReason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .length)
  }

  func testStreamErrorEventEmitsErrorPart() async throws {
    let chunks: [String] = [
      "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_e\",\"model\":\"gpt-4o\",\"status\":\"in_progress\"}}\n\n",
      "data: {\"type\":\"response.failed\",\"response\":{\"id\":\"resp_e\",\"status\":\"failed\",\"error\":{\"message\":\"Something went wrong\",\"code\":\"server_error\"}}}\n\n",
    ]
    let server = makeServer(.init(type: .streamChunks(chunks)))
    let model = server.responsesModel("gpt-4o")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let errors = parts.compactMap { part -> ModelStreamError? in
      guard case let .error(error) = part else { return nil }
      return error
    }
    XCTAssertEqual(errors.count, 1)
    XCTAssertEqual(errors.first?.message, "Something went wrong")

    guard let finish = parts.last, case let .finish(finishReason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .error)
  }
}
