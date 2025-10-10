import XCTest
@testable import AIKit

/// Comprehensive regression suite for Vercel AI SDK edge cases we still need to port.
///
/// Each test documents the exact Vercel implementation reference that motivates the expected behaviour.
@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class AIChatVercelEdgeCasesTests: XCTestCase {
    
    private var mockProvider: SimpleMockProvider!
    private var client: AIClient!
    private var model: LanguageModel!
    
    override func setUp() async throws {
        mockProvider = SimpleMockProvider()
        client = AIClient()
        model = mockProvider.languageModel("test-model")
    }
    
    private func waitForChatToBeReady(_ chat: AIChat, timeout: TimeInterval = 1.0) async {
        let nanosPerSecond: Double = 1_000_000_000
        let interval: UInt64 = 50_000_000 // 50ms
        let deadline = UInt64(timeout * nanosPerSecond)
        var elapsed: UInt64 = 0

        while chat.status != .ready && elapsed < deadline {
            try? await Task.sleep(nanoseconds: interval)
            elapsed += interval
        }
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:220-344)
    /// ensures streaming tool_call_start + tool_call_delta events populate tool invocations even before a final tool_call payload arrives.
    func testStreamingToolCallDeltasProduceAssistantToolInvocation() async {
        let chat = AIChat(client: client, model: model, tools: [])
        
        let toolCallId = "call_1"
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: ProviderChunk.ToolCallStreamingStart(
                    toolCallId: toolCallId,
                    toolName: "get_weather"
                ),
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 1,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: toolCallId,
                    toolName: "get_weather",
                    argsTextDelta: #"{"location":"San"#
                ),
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 2,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: toolCallId,
                    toolName: "get_weather",
                    argsTextDelta: #" Francisco"}"#
                ),
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .toolCalls,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 3,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        chat.input = "Use the weather tool"
        await chat.sendMessage()
        await waitForChatToBeReady(chat)
        
        guard let assistant = chat.messages.last(where: { $0.role == .assistant }) else {
            XCTFail("Expected assistant message to exist")
            return
        }

        // Expected final JSON arguments reconstructed from streaming deltas.
        let expectedArguments = #"{"location":"San Francisco"}"#
        XCTAssertEqual(
            assistant.toolCalls.first?.function.arguments,
            expectedArguments,
            "Streaming tool_call deltas should materialize a tool invocation mirroring Vercel's tool_call reconstruction."
        )
    }
    
    /// Vercel reference: stream-text-result.ts (vercel-sdk/packages/ai/core/generate-text/stream-text-result.ts:240-330)
    /// exposes the accumulated tool calls via the public result API so hooks can resubmit automatically.
    func testStreamTextResultExposesFinalToolCalls() async throws {
        let tool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Fetch weather details",
                parameters: .object(properties: ["location": .string()])
            ),
            execute: { _ in
                ToolResult.success(toolCallId: "call_1", text: "72°F and sunny")
            }
        )
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: ToolCall(
                    id: "call_1",
                    function: ToolCallFunction(
                        name: "get_weather",
                        arguments: #"{"location":"San Francisco"}"#
                    )
                ),
                usage: nil,
                finishReason: .toolCalls,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("What's the weather?")],
            tools: [tool],
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream {
                // Drain the stream so the tracker finalizes.
            }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let recordedToolCalls = await result.toolCalls
        XCTAssertEqual(
            recordedToolCalls.count,
            1,
            "StreamTextResult.toolCalls should expose the executed tool call for parity with Vercel's StreamTextResult."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:268-344)
    /// stores tool results alongside tool calls so the client can render them before resubmitting.
    func testStreamTextResultExposesToolResults() async throws {
        let tool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Fetch weather details",
                parameters: .object(properties: ["location": .string()])
            ),
            execute: { call in
                ToolResult.success(
                    toolCallId: call.id,
                    text: "72°F and sunny"
                )
            }
        )
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: ToolCall(
                    id: "call_1",
                    function: ToolCallFunction(
                        name: "get_weather",
                        arguments: #"{"location":"San Francisco"}"#
                    )
                ),
                usage: nil,
                finishReason: .toolCalls,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("What's the weather?")],
            tools: [tool],
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let recordedToolResults = await result.toolResults
        XCTAssertEqual(
            recordedToolResults.count,
            1,
            "StreamTextResult.toolResults should expose the tool execution output so clients can follow Vercel's auto-submit workflow."
        )
        
        XCTAssertEqual(
            recordedToolResults.first?.result.textValue,
            "72°F and sunny"
        )
    }

    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:220-344)
    /// reconstructs tool invocations even when only streaming start/delta parts are emitted.
    func testStreamTextResultTracksToolCallFromStreamingOnlyEvents() async {
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: ProviderChunk.ToolCallStreamingStart(
                    toolCallId: "call_1",
                    toolName: "lookup"
                ),
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 1,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: "call_1",
                    toolName: "lookup",
                    argsTextDelta: #"{"query":"weather"#
                ),
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .toolCalls,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 2,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: "call_1",
                    toolName: "lookup",
                    argsTextDelta: #" in SF"}"#
                ),
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("streaming tool call only")],
            tools: nil,
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let toolCalls = await result.toolCalls
        XCTAssertEqual(
            toolCalls.first?.function.arguments,
            #"{"query":"weather in SF"}"#,
            "Streaming start/delta events should be reconstructed into a completed tool call like Vercel's process-chat-response."
        )

    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:220-344)
    /// emits tool_call_streaming_start and tool_call_delta parts that surface through the client text stream.
    func testTextStreamEmitsToolCallStreamingEvents() async throws {
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: ProviderChunk.ToolCallStreamingStart(
                    toolCallId: "call_1",
                    toolName: "lookup"
                ),
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 1,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: ProviderChunk.ToolCallDelta(
                    toolCallId: "call_1",
                    toolName: "lookup",
                    argsTextDelta: #"{"q":"value"}"#
                ),
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("emit streaming events")],
            tools: nil,
            maxSteps: 1
        )
        
        var startEventObserved = false
        var deltaEventObserved = false
        
        do {
            for try await chunk in result.textStream {
                if chunk.toolCallStreamingStart?.toolCallId == "call_1" {
                    startEventObserved = true
                }
                if chunk.toolCallDelta?.toolCallId == "call_1" {
                    deltaEventObserved = true
                }
            }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        XCTAssertTrue(startEventObserved, "TextChunk.toolCallStreamingStart should surface streaming start events.")
        XCTAssertTrue(deltaEventObserved, "TextChunk.toolCallDelta should surface argument delta events.")
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:314-344)
    /// appends tool_result parts to the message stream; Vercel's hooks expect a dedicated tool message containing the result payload.
    func testStreamResponseIncludesToolResultMessage() async throws {
        let tool = Tool(
            function: ToolFunction(
                name: "get_weather",
                description: "Weather lookup",
                parameters: .object(properties: ["location": .string()])
            ),
            execute: { call in
                ToolResult.success(
                    toolCallId: call.id,
                    text: "72°F and sunny"
                )
            }
        )
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: ToolCall(
                    id: "call_1",
                    function: ToolCallFunction(
                        name: "get_weather",
                        arguments: #"{"location":"San Francisco"}"#
                    )
                ),
                usage: nil,
                finishReason: .toolCalls,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("need weather update")],
            tools: [tool],
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let response = await result.response
        XCTAssertTrue(
            response.messages.contains(where: { $0.role == .tool }),
            "StreamTextResponse.messages should include a tool role message for the executed tool result."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:362-380)
    /// captures usage and finish reason from the finish_message / finish_step parts emitted by providers.
    func testStreamTextResultCapturesUsageAndFinishReason() async {
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "Weather is 72°F.",
                toolCall: nil,
                usage: Usage(
                    promptTokens: 5,
                    completionTokens: 4,
                    promptCost: nil,
                    completionCost: nil,
                    currency: "USD"
                ),
                finishReason: .stop,
                additionalOutputs: nil,
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("tell me the weather")],
            tools: nil,
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let finishReason = await result.finishReason
        XCTAssertEqual(
            finishReason,
            .stop,
            "finish_message parts should propagate the finish reason."
        )
        
        let usage = await result.usage
        XCTAssertEqual(usage?.completionTokens, 4, "Usage emitted during streaming should be surfaced on StreamTextResult.")
    }

    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:138-212).
    /// Vercel captures streaming reasoning deltas and attaches them to the assistant message parts.
    func testAssistantMessageCapturesReasoningParts() async {
        let reasoningFragments = [
            "Analyzing user objectives.",
            "Cross-checking available data sources."
        ]
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.reasoning": try! encodeJSON(reasoningFragments)
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let chat = AIChat(client: client, model: model)
        chat.input = "Explain the plan."
        await chat.sendMessage()
        await waitForChatToBeReady(chat)
        
        guard let assistant = chat.messages.last(where: { $0.role == .assistant }) else {
            XCTFail("Expected assistant message to exist")
            return
        }
        
        let renderedContent = assistant.orderedContent.map { String(describing: $0) }.joined(separator: " | ")
        for fragment in reasoningFragments {
            XCTAssertTrue(
                renderedContent.contains(fragment),
                "Reasoning fragment '\(fragment)' should be preserved like Vercel's reasoning parts."
            )
        }
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:175-205).
    /// Redacted reasoning details are preserved alongside normal reasoning parts in the Vercel SDK.
    func testAssistantMessageCapturesRedactedReasoningSegments() async {
        let redactedEntry = ["data": "Sensitive customer token"]
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.reasoning.redacted": try! encodeJSON(redactedEntry)
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let chat = AIChat(client: client, model: model)
        chat.input = "Share secure plan."
        await chat.sendMessage()
        await waitForChatToBeReady(chat)
        
        guard let assistant = chat.messages.last(where: { $0.role == .assistant }) else {
            XCTFail("Expected assistant message to exist")
            return
        }
        
        let renderedContent = assistant.orderedContent.map { String(describing: $0) }.joined(separator: " | ")
        XCTAssertTrue(
            renderedContent.contains("Sensitive customer token"),
            "Redacted reasoning payloads should be surfaced to the client the way Vercel surfaces redacted_reasoning parts."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:172-183).
    /// Signature metadata attached to reasoning streams is surfaced by Vercel.
    func testAssistantMessageCapturesReasoningSignature() async {
        let signature = "sha256:abc123"
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.reasoning_signature": try! encodeJSON(["signature": signature])
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let chat = AIChat(client: client, model: model)
        chat.input = "Need validated reasoning."
        await chat.sendMessage()
        await waitForChatToBeReady(chat)
        
        guard let assistant = chat.messages.last(where: { $0.role == .assistant }) else {
            XCTFail("Expected assistant message to exist")
            return
        }
        
        let renderedContent = String(describing: assistant)
        XCTAssertTrue(
            renderedContent.contains(signature),
            "Reasoning signature should be preserved on the assistant message parts, matching Vercel behaviour."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:343-357).
    /// Message annotations emitted by the server are appended to the last message in Vercel.
    func testAssistantMessageCapturesAnnotations() async {
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.message_annotations": try! encodeJSON(["safety:block"])
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let chat = AIChat(client: client, model: model)
        chat.input = "Provide blocked content."
        await chat.sendMessage()
        await waitForChatToBeReady(chat)
        
        guard let assistant = chat.messages.last(where: { $0.role == .assistant }) else {
            XCTFail("Expected assistant message to exist")
            return
        }
        
        let renderedAssistant = String(describing: assistant)
        XCTAssertTrue(
            renderedAssistant.contains("safety:block"),
            "Message annotations from the stream must be attached to the assistant message just like Vercel's implementation."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:243-347).
    /// Stream data parts are accumulated separately from messages in Vercel's hook state.
    func testStreamTextResultAggregatesStreamData() async {
        let dataPayload: [[String: String]] = [
            ["type": "debug", "message": "retrieving documents"]
        ]
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.data": try! encodeJSON(dataPayload)
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("need debug info")],
            tools: nil,
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let extractedData: [[String: String]]? = extractValue(from: result, path: ["streamData"])
        XCTAssertEqual(
            extractedData?.count,
            1,
            "Stream data emitted from the model should be accumulated like Vercel's useChat hook."
        )
    }
    
    /// Vercel reference: process-chat-response.ts (vercel-sdk/packages/ai/node_modules/@ai-sdk/ui-utils/src/process-chat-response.ts:243-347).
    /// Multiple data parts must append in-order, mirroring Vercel's data stream accumulation.
    func testStreamTextResultAppendsMultipleStreamDataEntries() async {
        let firstPayload: [[String: String]] = [
            ["type": "debug", "message": "step1"]
        ]
        let secondPayload: [[String: String]] = [
            ["type": "debug", "message": "step2"]
        ]
        
        mockProvider.mockStreamingResponses["test-model"] = [
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: nil,
                additionalOutputs: [
                    "stream.data": try! encodeJSON(firstPayload)
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 0,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            ),
            ProviderChunk(
                delta: "",
                toolCall: nil,
                usage: nil,
                finishReason: .stop,
                additionalOutputs: [
                    "stream.data": try! encodeJSON(secondPayload)
                ],
                chunkId: UUID().uuidString,
                timestamp: Date(),
                chunkIndex: 1,
                stepId: nil,
                toolCallStreamingStart: nil,
                toolCallDelta: nil,
                stepStart: nil,
                stepFinish: nil
            )
        ]
        
        let result = await client.streamText(
            model,
            messages: [.user("multi data")],
            tools: nil,
            maxSteps: 1
        )
        
        do {
            for try await _ in result.textStream { }
        } catch {
            XCTFail("textStream threw error: \(error)")
        }
        
        let extractedData: [[String: String]]? = extractValue(from: result, path: ["streamData"])
        XCTAssertEqual(
            extractedData?.compactMap { $0["message"] },
            ["step1", "step2"],
            "Stream data should append sequentially as Vercel's implementation does."
        )
    }
}

// MARK: - Helpers

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

private func extractValue<T>(from root: Any, path: [String]) -> T? {
    var current: Any = root
    for key in path {
        let mirror = Mirror(reflecting: current)
        guard let next = mirror.children.first(where: { $0.label == key })?.value else {
            return nil
        }
        current = next
    }
    return current as? T
}
