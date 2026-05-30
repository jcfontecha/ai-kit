import XCTest
@testable import AIKitOpenAI
import AIKitProviders

final class OpenAIChatLanguageModelTests: XCTestCase {
  private var testPrompt: [ModelMessage] {
    [.user("Hello")]
  }

  private func makeServer() -> OpenAITestServer {
    OpenAITestServer(config: [
      OpenAITestServer.chatURL: .init(type: .jsonValue(.object([:])))
    ])
  }

  private func prepareJsonResponse(
    _ server: OpenAITestServer,
    content: String = "",
    toolCalls: [OpenAIChatToolCall]? = nil,
    usage: JSONValue? = .object([
      "prompt_tokens": .number(4),
      "completion_tokens": .number(30),
      "total_tokens": .number(34),
    ]),
    finishReason: String = "stop"
  ) {
    server.urls[OpenAITestServer.chatURL]?.response = .init(
      type: .jsonValue(.object([
        "id": .string("chatcmpl-95ZTZkhr0mHNKqerQfiwkuox3PHAd"),
        "object": .string("chat.completion"),
        "created": .number(1711115037),
        "model": .string("gpt-4o-2024-08-06"),
        "choices": .array([
          .object([
            "index": .number(0),
            "message": .object([
              "role": .string("assistant"),
              "content": .string(content),
              "tool_calls": toolCalls.flatMap { OpenAIJSON.encodeToJSONValue($0) },
            ].compactMapValues { $0 }),
            "finish_reason": .string(finishReason),
          ])
        ]),
        "usage": usage,
      ].compactMapValues { $0 }))
    )
  }

  func testExtractTextResponse() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "Hello, World!")

    let model = server.chatModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [.text("Hello, World!")])
  }

  func testExtractUsage() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "",
      usage: .object([
        "prompt_tokens": .number(20),
        "completion_tokens": .number(5),
        "total_tokens": .number(25),
      ])
    )

    let model = server.chatModel("gpt-4o")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.usage.inputTokens?.total, 20)
    XCTAssertEqual(response.usage.outputTokens?.total, 5)
  }

  func testExtractFinishReason() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "", finishReason: "stop")

    let model = server.chatModel("gpt-4o")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.finishReason, .stop)
  }

  func testUnknownFinishReason() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "", finishReason: "eos")

    let model = server.chatModel("gpt-4o")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.finishReason, .other)
  }

  func testToolCallResponse() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "",
      toolCalls: [
        .init(
          type: "function",
          id: "call_123",
          function: .init(name: "get_weather", arguments: "{\"location\":\"San Francisco\"}")
        )
      ],
      finishReason: "tool_calls"
    )

    let model = server.chatModel("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.finishReason, .toolCalls)
    XCTAssertTrue(result.content.contains { part in
      if case let .toolCall(call) = part {
        return call.toolCallID == "call_123" && call.toolName == "get_weather"
      }
      return false
    })
  }

  func testPassModelAndMessages() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "")

    let model = server.chatModel("gpt-4o")
    _ = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("gpt-4o"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ])
      ])
    )
  }

  func testPassOptions() async throws {
    let server = makeServer()
    prepareJsonResponse(server)

    let model = server.chatModel(
      "gpt-4o",
      options: .init(
        logitBias: ["50256": -100],
        logprobs: .topN(2),
        parallelToolCalls: false,
        user: "test-user-id",
        maxCompletionTokens: 256,
        store: true,
        serviceTier: .flex,
        promptCacheKey: "cache-key",
        safetyIdentifier: "safety-id"
      )
    )
    _ = try await model.generate(.init(messages: testPrompt))

    let body = server.calls.first?.requestBodyJSON
    guard case let .object(object)? = body else {
      return XCTFail("Expected object body")
    }
    XCTAssertEqual(object["logprobs"], .bool(true))
    XCTAssertEqual(object["top_logprobs"], .number(2))
    XCTAssertEqual(object["logit_bias"], .object(["50256": .number(-100)]))
    XCTAssertEqual(object["parallel_tool_calls"], .bool(false))
    XCTAssertEqual(object["user"], .string("test-user-id"))
    XCTAssertEqual(object["max_completion_tokens"], .number(256))
    XCTAssertEqual(object["store"], .bool(true))
    XCTAssertEqual(object["service_tier"], .string("flex"))
    XCTAssertEqual(object["prompt_cache_key"], .string("cache-key"))
    XCTAssertEqual(object["safety_identifier"], .string("safety-id"))
  }

  func testReasoningModelSendsDeveloperRoleAndOmitsTemperature() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "ok")

    let model = server.chatModel("o3", options: .init(reasoningEffort: .high, forceReasoning: true))
    _ = try await model.generate(.init(
      messages: [.system("You are helpful"), .user("Hello")],
      settings: .init(temperature: 0.7)
    ))

    guard case let .object(object)? = server.calls.first?.requestBodyJSON else {
      return XCTFail("Expected object body")
    }
    XCTAssertNil(object["temperature"])
    XCTAssertEqual(object["reasoning_effort"], .string("high"))
    if case let .array(messages)? = object["messages"], case let .object(first)? = messages.first {
      XCTAssertEqual(first["role"], .string("developer"))
    } else {
      XCTFail("Expected developer system message")
    }
  }

  func testPassToolsAndToolChoice() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "")

    let model = server.chatModel("gpt-4o")
    let schema = JSONSchema.object(properties: [
      "value": .string()
    ], required: ["value"], additionalProperties: false)

    _ = try await model.generate(.init(
      messages: testPrompt,
      tools: [
        ToolDefinition(name: "test-tool", description: "Test tool", inputSchema: schema),
      ],
      toolChoice: .tool(name: "test-tool")
    ))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("gpt-4o"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ]),
        "tools": .array([
          .object([
            "type": .string("function"),
            "function": .object([
              "name": .string("test-tool"),
              "description": .string("Test tool"),
              "parameters": .object(schema.value),
            ])
          ])
        ]),
        "tool_choice": .object([
          "type": .string("function"),
          "function": .object(["name": .string("test-tool")])
        ])
      ])
    )
  }

  func testResponseFormatJSONSchema() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "{\"name\": \"John\", \"age\": 30}")

    let model = server.chatModel("gpt-4o")
    let schema = JSONSchema.object(
      properties: ["name": .string(), "age": .number()],
      required: ["name", "age"],
      additionalProperties: false
    )

    _ = try await model.generate(.init(
      messages: testPrompt,
      responseFormat: .jsonSchema(schema: schema, name: "PersonResponse", description: "A person object")
    ))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("gpt-4o"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ]),
        "response_format": .object([
          "type": .string("json_schema"),
          "json_schema": .object([
            "schema": .object(schema.value),
            "strict": .bool(true),
            "name": .string("PersonResponse"),
            "description": .string("A person object"),
          ])
        ])
      ])
    )
  }

  func testProviderChatFactory() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "Hi")

    let transport = server.transport()
    let provider = createOpenAI(.init(
      apiKey: "test-api-key",
      transport: { request in try await transport.data(for: request) }
    ))
    let model = provider.chat("gpt-4o")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [.text("Hi")])
    XCTAssertEqual(server.calls.first?.requestHeaders["authorization"], "Bearer test-api-key")
  }
}
