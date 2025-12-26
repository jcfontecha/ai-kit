import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterChatGenerateTests: XCTestCase {
  private let testImageURL = "data:image/png;base64,AAECAw=="

  private var testImageBase64: String {
    testImageURL.split(separator: ",").last.map(String.init) ?? ""
  }

  private var testPrompt: [ModelMessage] {
    [.user("Hello")]
  }

  private func makeServer() -> OpenRouterTestServer {
    OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .jsonValue(.object([:])))
    ])
  }

  private func prepareJsonResponse(
    _ server: OpenRouterTestServer,
    content: String = "",
    reasoning: String? = nil,
    reasoningDetails: [ReasoningDetailUnion]? = nil,
    images: [OpenRouterImageResponse]? = nil,
    toolCalls: [OpenRouterChatToolCall]? = nil,
    usage: JSONValue? = .object([
      "prompt_tokens": .number(4),
      "completion_tokens": .number(30),
      "total_tokens": .number(34),
    ]),
    finishReason: String = "stop"
  ) {
    server.urls["https://openrouter.ai/api/v1/chat/completions"]?.response = .init(
      type: .jsonValue(.object([
        "id": .string("chatcmpl-95ZTZkhr0mHNKqerQfiwkuox3PHAd"),
        "object": .string("chat.completion"),
        "created": .number(1711115037),
        "model": .string("gpt-3.5-turbo-0125"),
        "choices": .array([
          .object([
            "index": .number(0),
            "message": .object([
              "role": .string("assistant"),
              "content": .string(content),
              "reasoning": reasoning.map(JSONValue.string),
              "reasoning_details": reasoningDetails.flatMap { OpenRouterJSON.encodeToJSONValue($0) },
              "images": images.flatMap { OpenRouterJSON.encodeToJSONValue($0) },
              "tool_calls": toolCalls.flatMap { OpenRouterJSON.encodeToJSONValue($0) },
            ].compactMapValues { $0 }),
            "finish_reason": .string(finishReason),
          ])
        ]),
        "usage": usage,
        "system_fingerprint": .string("fp_3bc1b5746c"),
      ].compactMapValues { $0 }))
    )
  }

  func testExtractTextResponse() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "Hello, World!")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
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

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.usage.inputTokens?.total, 20)
    XCTAssertEqual(response.usage.outputTokens?.total, 5)
  }

  func testExtractLogprobsDoesNotThrow() async throws {
    let server = makeServer()
    let logprobs = JSONValue.object([
      "content": .array([
        .object([
          "token": .string("Hello"),
          "logprob": .number(-0.0009),
          "top_logprobs": .array([
            .object([
              "token": .string("Hello"),
              "logprob": .number(-0.0009),
            ])
          ])
        ])
      ])
    ])

    server.urls["https://openrouter.ai/api/v1/chat/completions"]?.response = .init(
      type: .jsonValue(.object([
        "id": .string("chatcmpl-95ZTZkhr0mHNKqerQfiwkuox3PHAd"),
        "model": .string("gpt-3.5-turbo-0125"),
        "choices": .array([
          .object([
            "index": .number(0),
            "message": .object([
              "role": .string("assistant"),
              "content": .string(""),
            ]),
            "logprobs": logprobs,
            "finish_reason": .string("stop"),
          ])
        ]),
        "usage": .object([
          "prompt_tokens": .number(4),
          "completion_tokens": .number(30),
          "total_tokens": .number(34),
        ]),
      ]))
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("openai/gpt-3.5-turbo", settings: .init(logprobs: .top(1)))
    _ = try await model.generate(.init(messages: testPrompt))
  }

  func testExtractFinishReason() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "", finishReason: "stop")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.finishReason, .stop)
  }

  func testUnknownFinishReason() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "", finishReason: "eos")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let response = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(response.finishReason, .other)
  }

  func testExtractReasoningFromReasoningField() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "Hello!",
      reasoning: "I need to think about this... The user said hello, so I should respond with a greeting."
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [
      .reasoning("I need to think about this... The user said hello, so I should respond with a greeting."),
      .text("Hello!")
    ])
  }

  func testExtractReasoningFromReasoningDetails() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "Hello!",
      reasoningDetails: [
        .text(.init(type: .text, text: "Let me analyze this request...", signature: nil, id: nil, format: nil, index: nil)),
        .summary(.init(type: .summary, summary: "The user wants a greeting response.", id: nil, format: nil, index: nil)),
      ]
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let result = try await model.generate(.init(messages: testPrompt))

    guard result.content.count == 3 else {
      XCTFail("Expected reasoning parts and text")
      return
    }

    if case let .reasoning(first, metadata) = result.content[0] {
      XCTAssertEqual(first, "Let me analyze this request...")
      XCTAssertEqual(
        metadata?["openrouter"],
        .object([
          "reasoning_details": .array([
            .object([
              "type": .string("reasoning.text"),
              "text": .string("Let me analyze this request..."),
            ])
          ])
        ])
      )
    } else {
      XCTFail("Expected first reasoning part")
    }

    if case let .reasoning(second, metadata) = result.content[1] {
      XCTAssertEqual(second, "The user wants a greeting response.")
      XCTAssertEqual(
        metadata?["openrouter"],
        .object([
          "reasoning_details": .array([
            .object([
              "type": .string("reasoning.summary"),
              "summary": .string("The user wants a greeting response."),
            ])
          ])
        ])
      )
    } else {
      XCTFail("Expected second reasoning part")
    }

    XCTAssertEqual(result.content.last, .text("Hello!"))
  }

  func testEncryptedReasoningDetails() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "Hello!",
      reasoningDetails: [
        .encrypted(.init(type: .encrypted, data: "encrypted_reasoning_data_here", id: nil, format: nil, index: nil))
      ]
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let result = try await model.generate(.init(messages: testPrompt))

    guard result.content.count == 2 else {
      XCTFail("Expected reasoning and text")
      return
    }

    if case let .reasoning(text, metadata) = result.content[0] {
      XCTAssertEqual(text, "[REDACTED]")
      XCTAssertEqual(
        metadata?["openrouter"],
        .object([
          "reasoning_details": .array([
            .object([
              "type": .string("reasoning.encrypted"),
              "data": .string("encrypted_reasoning_data_here"),
            ])
          ])
        ])
      )
    } else {
      XCTFail("Expected reasoning part")
    }
  }

  func testPrioritizeReasoningDetailsOverReasoning() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "Hello!",
      reasoning: "This should be ignored when reasoning_details is present",
      reasoningDetails: [
        .text(.init(type: .text, text: "Processing from reasoning_details...", signature: nil, id: nil, format: nil, index: nil)),
        .summary(.init(type: .summary, summary: "Summary from reasoning_details", id: nil, format: nil, index: nil)),
      ]
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content.first, .reasoning("Processing from reasoning_details...", metadata: [
      "openrouter": .object([
        "reasoning_details": .array([
          .object([
            "type": .string("reasoning.text"),
            "text": .string("Processing from reasoning_details..."),
          ])
        ])
      ])
    ]))
    XCTAssertEqual(result.content[1], .reasoning("Summary from reasoning_details", metadata: [
      "openrouter": .object([
        "reasoning_details": .array([
          .object([
            "type": .string("reasoning.summary"),
            "summary": .string("Summary from reasoning_details"),
          ])
        ])
      ])
    ]))
  }

  func testOverrideFinishReasonWithToolCallsAndEncryptedReasoning() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "",
      reasoningDetails: [
        .encrypted(.init(type: .encrypted, data: "encrypted_reasoning_data_here", id: nil, format: nil, index: nil))
      ],
      toolCalls: [
        .init(
          type: "function",
          id: "call_123",
          function: .init(name: "get_weather", arguments: "{\"location\":\"San Francisco\"}")
        )
      ],
      finishReason: "stop"
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
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

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    _ = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("anthropic/claude-3.5-sonnet"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ])
      ])
    )
  }

  func testPassModelsArray() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat(
      "anthropic/claude-3.5-sonnet",
      settings: .init(models: ["anthropic/claude-2", "gryphe/mythomax-l2-13b"])
    )
    _ = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("anthropic/claude-3.5-sonnet"),
        "models": .array([.string("anthropic/claude-2"), .string("gryphe/mythomax-l2-13b")]),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ])
      ])
    )
  }

  func testPassSettings() async throws {
    let server = makeServer()
    prepareJsonResponse(server)

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat(
      "openai/gpt-3.5-turbo",
      settings: .init(
        logitBias: [50256: -100],
        logprobs: .top(2),
        parallelToolCalls: false,
        user: "test-user-id"
      )
    )
    _ = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("openai/gpt-3.5-turbo"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ]),
        "logprobs": .bool(true),
        "top_logprobs": .number(2),
        "logit_bias": .object(["50256": .number(-100)]),
        "parallel_tool_calls": .bool(false),
        "user": .string("test-user-id"),
      ])
    )
  }

  func testPassToolsAndToolChoice() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
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
        "model": .string("anthropic/claude-3.5-sonnet"),
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

  func testPassHeaders() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "")

    let provider = createOpenRouter(.init(
      apiKey: "test-api-key",
      headers: ["Custom-Provider-Header": "provider-header-value"],
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.chat("openai/gpt-3.5-turbo")
    _ = try await model.generate(.init(messages: testPrompt, headers: ["Custom-Request-Header": "request-header-value"]))

    XCTAssertEqual(
      server.calls.first?.requestHeaders,
      [
        "authorization": "Bearer test-api-key",
        "content-type": "application/json",
        "custom-provider-header": "provider-header-value",
        "custom-request-header": "request-header-value",
        "user-agent": "ai-sdk/openrouter/0.0.0-test",
      ]
    )
  }

  func testResponseFormatJSONSchema() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "{\"name\": \"John\", \"age\": 30}")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
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
        "model": .string("anthropic/claude-3.5-sonnet"),
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

  func testResponseFormatDefaultName() async throws {
    let server = makeServer()
    prepareJsonResponse(server, content: "{\"name\": \"John\", \"age\": 30}")

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let schema = JSONSchema.object(
      properties: ["name": .string(), "age": .number()],
      required: ["name", "age"],
      additionalProperties: false
    )

    _ = try await model.generate(.init(
      messages: testPrompt,
      responseFormat: .jsonSchema(schema: schema)
    ))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "model": .string("anthropic/claude-3.5-sonnet"),
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
            "name": .string("response"),
          ])
        ])
      ])
    )
  }

  func testPassImages() async throws {
    let server = makeServer()
    prepareJsonResponse(
      server,
      content: "",
      images: [
        .init(type: "image_url", imageURL: .init(url: testImageURL))
      ],
      usage: .object([
        "prompt_tokens": .number(53),
        "completion_tokens": .number(17),
        "total_tokens": .number(70),
      ])
    )

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let result = try await model.generate(.init(messages: testPrompt))

    XCTAssertEqual(result.content, [
      .file(.init(data: Data(base64Encoded: testImageBase64) ?? Data(), mediaType: "image/png"))
    ])
  }
}
