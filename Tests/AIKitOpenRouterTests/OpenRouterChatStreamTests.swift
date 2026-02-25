import XCTest
@testable import AIKitOpenRouter
import AIKitProviders

final class OpenRouterChatStreamTests: XCTestCase {
  private let testPrompt: [ModelMessage] = [.user("Hello")]

  private func makeProvider(server: OpenRouterTestServer, extraBody: [String: JSONValue]? = nil, settings: OpenRouterChatSettings = .init()) -> OpenRouterProviderClient {
    var providerSettings = OpenRouterProviderSettings(
      apiKey: "test-api-key",
      headers: [:],
      compatibility: .strict,
      transport: server.transport()
    )
    providerSettings.extraBody = extraBody
    return createOpenRouter(providerSettings)
  }

  private func streamChunksForTextDeltas(
    id: String = "chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP",
    model: String = "gpt-3.5-turbo-0613",
    content: [String],
    finishReason: String = "stop",
    usage: String
  ) -> [String] {
    var chunks: [String] = []
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n\n"
    )
    for text in content {
      chunks.append(
        "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"system_fingerprint\":null,\"choices\":[{\"index\":1,\"delta\":{\"content\":\"\(text)\"},\"finish_reason\":null}]}\n\n"
      )
    }
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(finishReason)\",\"logprobs\":null}]}\n\n"
    )
    chunks.append(
      "data: {\"id\":\"\(id)\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"\(model)\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":\(usage)}\n\n"
    )
    chunks.append("data: [DONE]\n\n")
    return chunks
  }

  func testStreamTextDeltas() async throws {
    let chunks = streamChunksForTextDeltas(
      content: ["Hello", ", ", "World!"],
      finishReason: "stop",
      usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")

    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    // Verify metadata is emitted for each chunk (id + model).
    XCTAssertEqual(parts.prefix(4).compactMap { part -> (String, String)? in
      guard case let .responseMetadata(meta) = part else { return nil }
      return (meta.id, meta.modelID)
    }.count, 4)

    // Verify text events.
    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["Hello", ", ", "World!"])

    // Verify finish.
    guard let finish = parts.last, case let .finish(finishReason, usage, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .stop)
    XCTAssertEqual(usage.inputTokens?.total, 17)
    XCTAssertEqual(usage.outputTokens?.total, 227)

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"] {
      XCTAssertEqual(usageMeta["promptTokens"], .number(17))
      XCTAssertEqual(usageMeta["completionTokens"], .number(227))
      XCTAssertEqual(usageMeta["totalTokens"], .number(244))
    } else {
      XCTFail("Expected openrouter usage metadata")
    }
  }

  func testStreamIncludesUpstreamInferenceCostInFinishMetadata() async throws {
    let chunks = streamChunksForTextDeltas(
      content: ["Hello"],
      usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227,\"cost_details\":{\"upstream_inference_cost\":0.0036}}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"],
       case let .object(costDetails)? = usageMeta["costDetails"] {
      XCTAssertEqual(costDetails["upstreamInferenceCost"], .number(0.0036))
    } else {
      XCTFail("Expected upstreamInferenceCost in providerMetadata")
    }
  }

  func testStreamIncludesCostAndUpstreamInferenceCostInFinishMetadata() async throws {
    let chunks = streamChunksForTextDeltas(
      content: ["Hello"],
      usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227,\"cost\":0.0042,\"cost_details\":{\"upstream_inference_cost\":0.0036}}"
    )

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .object(usageMeta)? = openrouter["usage"],
       case let .number(cost)? = usageMeta["cost"],
       case let .object(costDetails)? = usageMeta["costDetails"] {
      XCTAssertEqual(cost, 0.0042)
      XCTAssertEqual(costDetails["upstreamInferenceCost"], .number(0.0036))
    } else {
      XCTFail("Expected cost and upstreamInferenceCost in providerMetadata")
    }
  }

  func testStreamPrioritizesReasoningDetailsOverReasoning() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning\":\"This should be ignored...\",\"reasoning_details\":[{\"type\":\"reasoning.text\",\"text\":\"Let me think about this...\"}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning\":\"Also ignored\",\"reasoning_details\":[{\"type\":\"reasoning.summary\",\"summary\":\"User wants a greeting\"},{\"type\":\"reasoning.encrypted\",\"data\":\"secret\"}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning\":\"This reasoning is used\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello!\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-reasoning\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":17,\"completion_tokens\":30,\"total_tokens\":47}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let reasoningDeltas = parts.compactMap { part -> String? in
      guard case let .reasoningDelta(_, text, _) = part else { return nil }
      return text
    }

    XCTAssertEqual(reasoningDeltas, [
      "Let me think about this...",
      "User wants a greeting",
      "[REDACTED]",
      "This reasoning is used",
    ])
  }

  func testStreamEmitsReasoningDetailsInProviderMetadataForAllReasoningDeltaChunks() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-metadata-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning_details\":[{\"type\":\"reasoning.text\",\"text\":\"First reasoning chunk\"}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-metadata-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_details\":[{\"type\":\"reasoning.summary\",\"summary\":\"Summary reasoning\"}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-metadata-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_details\":[{\"type\":\"reasoning.encrypted\",\"data\":\"encrypted_data\"}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-metadata-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-metadata-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":17,\"completion_tokens\":30,\"total_tokens\":47}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let reasoningDeltaParts = parts.compactMap { part -> ModelStreamPart? in
      guard case .reasoningDelta = part else { return nil }
      return part
    }
    XCTAssertEqual(reasoningDeltaParts.count, 3)

    func openrouterReasoningDetails(from part: ModelStreamPart) -> JSONValue? {
      switch part {
      case .reasoningStart(_, let providerMetadata),
           .reasoningDelta(_, _, let providerMetadata):
        guard case let .object(openrouter)? = providerMetadata?["openrouter"] else { return nil }
        return openrouter["reasoning_details"]
      default:
        return nil
      }
    }

    XCTAssertEqual(
      openrouterReasoningDetails(from: reasoningDeltaParts[0]),
      .array([
        .object([
          "type": .string("reasoning.text"),
          "text": .string("First reasoning chunk"),
        ])
      ])
    )
    XCTAssertEqual(
      openrouterReasoningDetails(from: reasoningDeltaParts[1]),
      .array([
        .object([
          "type": .string("reasoning.summary"),
          "summary": .string("Summary reasoning"),
        ])
      ])
    )
    XCTAssertEqual(
      openrouterReasoningDetails(from: reasoningDeltaParts[2]),
      .array([
        .object([
          "type": .string("reasoning.encrypted"),
          "data": .string("encrypted_data"),
        ])
      ])
    )

    let reasoningStart = parts.first { part in
      if case .reasoningStart = part { return true }
      return false
    }
    XCTAssertNotNil(reasoningStart)
    if let reasoningStart {
      XCTAssertEqual(
        openrouterReasoningDetails(from: reasoningStart),
        .array([
          .object([
            "type": .string("reasoning.text"),
            "text": .string("First reasoning chunk"),
          ])
        ])
      )
    }
  }

  func testStreamMaintainsReasoningOrderWhenContentComesAfterReasoning() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"reasoning\":\"I need to think about this step by step...\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning\":\" First, I should analyze the request.\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning\":\" Then I should provide a helpful response.\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello! \"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"How can I help you today?\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-order-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-3.5-turbo-0125\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":17,\"completion_tokens\":30,\"total_tokens\":47}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let types = parts.map { part -> String in
      switch part {
      case .reasoningStart: return "reasoning-start"
      case .reasoningDelta: return "reasoning-delta"
      case .reasoningEnd: return "reasoning-end"
      case .textStart: return "text-start"
      case .textDelta: return "text-delta"
      case .textEnd: return "text-end"
      default: return "other"
      }
    }

    guard let reasoningStartIndex = types.firstIndex(of: "reasoning-start"),
          let reasoningEndIndex = types.firstIndex(of: "reasoning-end"),
          let textStartIndex = types.firstIndex(of: "text-start") else {
      return XCTFail("Expected reasoning and text events")
    }

    XCTAssertLessThan(reasoningStartIndex, textStartIndex)
    XCTAssertLessThan(reasoningEndIndex, textStartIndex)

    let reasoningDeltas = parts.compactMap { part -> String? in
      guard case let .reasoningDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(reasoningDeltas, [
      "I need to think about this step by step...",
      " First, I should analyze the request.",
      " Then I should provide a helpful response.",
    ])

    let textDeltas = parts.compactMap { part -> String? in
      guard case let .textDelta(_, text, _) = part else { return nil }
      return text
    }
    XCTAssertEqual(textDeltas, ["Hello! ", "How can I help you today?"])
  }

  func testStreamToolDeltas() async throws {
    let chunks: [String] = [
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"role":"assistant","content":null,"tool_calls":[{"index":0,"id":"call_O17Uplv4lJvD6DVdIvFFeRMw","type":"function","function":{"name":"test-tool","arguments":""}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\""}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"value"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\":\""}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Spark"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"le"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":" Day"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"}"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"tool_calls"}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[],"usage":{"prompt_tokens":53,"completion_tokens":17,"total_tokens":70}}"# + "\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")

    let toolSchema = JSONSchema.object(
      properties: ["value": .string()],
      required: ["value"],
      additionalProperties: false
    )

    let parts = try await collectStream(model.stream(.init(
      messages: testPrompt,
      tools: [ToolDefinition(name: "test-tool", inputSchema: toolSchema)]
    )))

    let toolInputEvents = parts.compactMap { part -> ModelStreamPart? in
      switch part {
      case .toolInputStart, .toolInputDelta, .toolCall:
        return part
      default:
        return nil
      }
    }
    XCTAssertTrue(toolInputEvents.contains { part in
      if case let .toolInputStart(id, toolName, _, _, _, _) = part {
        return id == "call_O17Uplv4lJvD6DVdIvFFeRMw" && toolName == "test-tool"
      }
      return false
    })

    let deltas = parts.compactMap { part -> String? in
      guard case let .toolInputDelta(id, delta, _) = part, id == "call_O17Uplv4lJvD6DVdIvFFeRMw" else { return nil }
      return delta
    }
    XCTAssertEqual(deltas, ["{\"", "value", "\":\"", "Spark", "le", " Day", "\"}"])

    let toolCall = parts.first { part in
      if case .toolCall = part { return true }
      return false
    }
    XCTAssertNotNil(toolCall)
    if let toolCall, case let .toolCall(call) = toolCall {
      XCTAssertEqual(call.toolCallID, "call_O17Uplv4lJvD6DVdIvFFeRMw")
      XCTAssertEqual(call.toolName, "test-tool")
      XCTAssertEqual(call.inputJSON, "{\"value\":\"Sparkle Day\"}")

      if case let .object(openrouter)? = call.providerMetadata?["openrouter"] {
        XCTAssertEqual(openrouter["reasoning_details"], .array([]))
      } else {
        XCTFail("Expected openrouter reasoning_details metadata on tool call")
      }
    }
  }

  func testStreamToolCallSentInOneChunkEmitsToolInputEnd() async throws {
    let chunks: [String] = [
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{"role":"assistant","content":null,"tool_calls":[{"index":0,"id":"call_O17Uplv4lJvD6DVdIvFFeRMw","type":"function","function":{"name":"test-tool","arguments":"{\"value\":\"Sparkle Day\"}"}}]},"logprobs":null,"finish_reason":null}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[{"index":0,"delta":{},"logprobs":null,"finish_reason":"tool_calls"}]}"# + "\n\n",
      #"data: {"id":"chatcmpl-96aZqmeDpA9IPD6tACY8djkMsJCMP","object":"chat.completion.chunk","created":1711357598,"model":"gpt-3.5-turbo-0125","system_fingerprint":"fp_3bc1b5746c","choices":[],"usage":{"prompt_tokens":53,"completion_tokens":17,"total_tokens":70}}"# + "\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let toolSchema = JSONSchema.object(
      properties: ["value": .string()],
      required: ["value"],
      additionalProperties: false
    )

    let parts = try await collectStream(model.stream(.init(
      messages: testPrompt,
      tools: [ToolDefinition(name: "test-tool", inputSchema: toolSchema)]
    )))

    XCTAssertTrue(parts.contains { part in
      if case let .toolInputEnd(id, _) = part { return id == "call_O17Uplv4lJvD6DVdIvFFeRMw" }
      return false
    })
  }

  func testStreamOverridesFinishReasonToToolCallsWhenToolCallsAndEncryptedReasoningPresent() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-gemini3\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"google/gemini-3-pro\",\"system_fingerprint\":\"fp_gemini3\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"reasoning_details\":[{\"type\":\"reasoning.encrypted\",\"data\":\"encrypted_thoughtsig_data\"}],\"tool_calls\":[{\"index\":0,\"id\":\"call_123\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"{}\"}}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-gemini3\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"google/gemini-3-pro\",\"system_fingerprint\":\"fp_gemini3\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-gemini3\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"google/gemini-3-pro\",\"system_fingerprint\":\"fp_gemini3\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(finishReason, _, _) = finish else {
      return XCTFail("Expected finish")
    }
    XCTAssertEqual(finishReason, .toolCalls)
  }

  func testStreamImages() async throws {
    let imageURL = "data:image/png;base64,AAECAw=="
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-image\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"images\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"\(imageURL)\"}}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-image\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-image\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    let files = parts.compactMap { part -> GeneratedFile? in
      guard case let .file(file) = part else { return nil }
      return file
    }
    XCTAssertEqual(files.count, 1)
    XCTAssertEqual(files.first?.mediaType, "image/png")
    XCTAssertEqual(files.first?.data, Data(base64Encoded: "AAECAw=="))
  }

  func testStreamErrorPartsIncludeStructuredError() async throws {
    let chunks: [String] = [
      "data: {\"error\":{\"message\":\"The server had an error processing your request.\",\"type\":\"server_error\",\"param\":null,\"code\":null}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard parts.count >= 2 else { return XCTFail("Expected error and finish") }
    if case let .error(error) = parts[0] {
      XCTAssertEqual(error.message, "The server had an error processing your request.")
      XCTAssertEqual(error.type, "server_error")
      XCTAssertEqual(error.code, .null)
      XCTAssertEqual(error.param, .null)
    } else {
      XCTFail("Expected error part")
    }
    if case let .finish(finishReason, _, providerMetadata) = parts[1] {
      XCTAssertEqual(finishReason, .error)
      if case let .object(openrouter)? = providerMetadata?["openrouter"] {
        XCTAssertEqual(openrouter["usage"], .object([:]))
      } else {
        XCTFail("Expected empty usage metadata")
      }
    } else {
      XCTFail("Expected finish part")
    }
  }

  func testStreamUnparsableStreamPartsEmitErrorAndFinish() async throws {
    let chunks: [String] = [
      "data: {unparsable}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    XCTAssertEqual(parts.count, 2)
    if case .error = parts[0] {
      // message content is not stable; parity only requires an error part is emitted.
    } else {
      XCTFail("Expected error part")
    }
    if case let .finish(finishReason, _, providerMetadata) = parts[1] {
      XCTAssertEqual(finishReason, .error)
      if case let .object(openrouter)? = providerMetadata?["openrouter"] {
        XCTAssertEqual(openrouter["usage"], .object([:]))
      } else {
        XCTFail("Expected empty usage metadata")
      }
    } else {
      XCTFail("Expected finish part")
    }
  }

  func testStreamPassesMessagesModelAndStreamOptions() async throws {
    let chunks = streamChunksForTextDeltas(content: [], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    _ = try await collectStream(model.stream(.init(messages: testPrompt)))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "stream": .bool(true),
        "stream_options": .object(["include_usage": .bool(true)]),
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

  func testStreamPassesHeaders() async throws {
    let chunks = streamChunksForTextDeltas(content: [], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(
      apiKey: "test-api-key",
      headers: ["Custom-Provider-Header": "provider-header-value"],
      compatibility: .strict,
      transport: server.transport()
    ))

    let model = provider.chat("openai/gpt-3.5-turbo")
    _ = try await collectStream(model.stream(.init(
      messages: testPrompt,
      headers: ["Custom-Request-Header": "request-header-value"]
    )))

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

  func testStreamPassesExtraBody() async throws {
    let chunks = streamChunksForTextDeltas(content: [], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(
      apiKey: "test-api-key",
      compatibility: .strict,
      transport: server.transport(),
      extraBody: [
        "custom_field": .string("custom_value"),
        "providers": .object([
          "anthropic": .object(["custom_field": .string("custom_value")]),
        ]),
      ]
    ))
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    _ = try await collectStream(model.stream(.init(messages: testPrompt)))

    if case let .object(body)? = server.calls.first?.requestBodyJSON {
      XCTAssertEqual(body["custom_field"], .string("custom_value"))
      if case let .object(providers)? = body["providers"],
         case let .object(anthropic)? = providers["anthropic"] {
        XCTAssertEqual(anthropic["custom_field"], .string("custom_value"))
      } else {
        XCTFail("Expected providers.anthropic.custom_field")
      }
    } else {
      XCTFail("Expected request body object")
    }
  }

  func testStreamPassesResponseFormatJSONSchema() async throws {
    let chunks = streamChunksForTextDeltas(content: ["{\"name\":\"John\",\"age\":30}"], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")

    let schema = JSONSchema.object(
      properties: ["name": .string(), "age": .number()],
      required: ["name", "age"],
      additionalProperties: false
    )

    _ = try await collectStream(model.stream(.init(
      messages: testPrompt,
      responseFormat: .jsonSchema(schema: schema, name: "PersonResponse", description: "A person object")
    )))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "stream": .bool(true),
        "stream_options": .object(["include_usage": .bool(true)]),
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

  func testStreamPassesResponseFormatAndToolsTogether() async throws {
    let chunks = streamChunksForTextDeltas(content: ["{\"name\":\"John\",\"age\":30}"], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")

    let schema = JSONSchema.object(
      properties: ["name": .string(), "age": .number()],
      required: ["name", "age"],
      additionalProperties: false
    )
    let toolSchema = JSONSchema.object(properties: ["value": .string()], required: ["value"], additionalProperties: false)

    _ = try await collectStream(model.stream(.init(
      messages: testPrompt,
      responseFormat: .jsonSchema(schema: schema, name: "PersonResponse", description: "A person object"),
      tools: [ToolDefinition(name: "test-tool", description: "Test tool", inputSchema: toolSchema)],
      toolChoice: .tool(name: "test-tool")
    )))

    if case let .object(body)? = server.calls.first?.requestBodyJSON {
      XCTAssertEqual(body["tool_choice"], .object(["type": .string("function"), "function": .object(["name": .string("test-tool")])]))
      XCTAssertNotNil(body["tools"])
      XCTAssertNotNil(body["response_format"])
    } else {
      XCTFail("Expected request body object")
    }
  }

  func testStreamPassesDebugSettings() async throws {
    let chunks = streamChunksForTextDeltas(content: ["Hello"], usage: "{\"prompt_tokens\":17,\"total_tokens\":244,\"completion_tokens\":227}")
    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])

    let provider = createOpenRouter(.init(apiKey: "test-api-key", compatibility: .strict, transport: server.transport()))
    let debugModel = provider.chat("anthropic/claude-3.5-sonnet", settings: .init(debug: .init(echoUpstreamBody: true)))

    _ = try await collectStream(debugModel.stream(.init(messages: testPrompt)))

    XCTAssertEqual(
      server.calls.first?.requestBodyJSON,
      .object([
        "stream": .bool(true),
        "stream_options": .object(["include_usage": .bool(true)]),
        "model": .string("anthropic/claude-3.5-sonnet"),
        "messages": .array([
          .object([
            "role": .string("user"),
            "content": .string("Hello"),
          ])
        ]),
        "debug": .object([
          "echo_upstream_body": .bool(true),
        ])
      ])
    )
  }

  func testStreamIncludesFileAnnotationsInFinishProviderMetadata() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-file-annotations\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"The title is Bitcoin.\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-file-annotations\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"annotations\":[{\"type\":\"file\",\"file\":{\"hash\":\"abc123def456\",\"name\":\"bitcoin.pdf\",\"content\":[{\"type\":\"text\",\"text\":\"Page 1 content\"},{\"type\":\"text\",\"text\":\"Page 2 content\"}]}}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-file-annotations\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-file-annotations\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":20,\"total_tokens\":120}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .array(annotations)? = openrouter["annotations"] {
      XCTAssertEqual(annotations.count, 1)
      if case let .object(first)? = annotations.first,
         case let .object(file)? = first["file"],
         case let .string(hash)? = file["hash"] {
        XCTAssertEqual(hash, "abc123def456")
      } else {
        XCTFail("Expected file annotation payload")
      }
    } else {
      XCTFail("Expected annotations in finish metadata")
    }
  }

  func testStreamAccumulatesMultipleFileAnnotations() async throws {
    let chunks: [String] = [
      "data: {\"id\":\"chatcmpl-multi-files\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Comparing two documents.\"},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-multi-files\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"annotations\":[{\"type\":\"file\",\"file\":{\"hash\":\"hash1\",\"name\":\"doc1.pdf\",\"content\":[{\"type\":\"text\",\"text\":\"Doc 1\"}]}}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-multi-files\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{\"annotations\":[{\"type\":\"file\",\"file\":{\"hash\":\"hash2\",\"name\":\"doc2.pdf\",\"content\":[{\"type\":\"text\",\"text\":\"Doc 2\"}]}}]},\"logprobs\":null,\"finish_reason\":null}]}\n\n",
      "data: {\"id\":\"chatcmpl-multi-files\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[{\"index\":0,\"delta\":{},\"logprobs\":null,\"finish_reason\":\"stop\"}]}\n\n",
      "data: {\"id\":\"chatcmpl-multi-files\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4o-mini\",\"system_fingerprint\":\"fp_3bc1b5746c\",\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":20,\"total_tokens\":120}}\n\n",
      "data: [DONE]\n\n",
    ]

    let server = OpenRouterTestServer(config: [
      "https://openrouter.ai/api/v1/chat/completions": .init(type: .streamChunks(chunks))
    ])
    let provider = makeProvider(server: server)
    let model = provider.chat("anthropic/claude-3.5-sonnet")
    let parts = try await collectStream(model.stream(.init(messages: testPrompt)))

    guard let finish = parts.last, case let .finish(_, _, providerMetadata) = finish else {
      return XCTFail("Expected finish")
    }

    if case let .object(openrouter)? = providerMetadata?["openrouter"],
       case let .array(annotations)? = openrouter["annotations"] {
      XCTAssertEqual(annotations.count, 2)
      if case let .object(first)? = annotations.first,
         case let .object(file)? = first["file"],
         case let .string(hash)? = file["hash"] {
        XCTAssertEqual(hash, "hash1")
      } else {
        XCTFail("Expected first file annotation")
      }
      if case let .object(second)? = annotations.last,
         case let .object(file)? = second["file"],
         case let .string(hash)? = file["hash"] {
        XCTAssertEqual(hash, "hash2")
      } else {
        XCTFail("Expected second file annotation")
      }
    } else {
      XCTFail("Expected annotations in finish metadata")
    }
  }
}
