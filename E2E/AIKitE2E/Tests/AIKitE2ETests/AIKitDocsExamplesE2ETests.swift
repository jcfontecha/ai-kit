import XCTest
import AIKit
import AIKitCore
import AIKitOpenAI
import AIKitOpenRouter
import AIKitMacro

@AIModel
private struct DocsWeatherInput: Codable, Sendable, Equatable {
  @Field("City name", minLength: 1, maxLength: 100)
  var city: String
}

final class AIKitDocsExamplesE2ETests: XCTestCase {
  func testDocsSwiftSnippetInventory() throws {
    let expectedCounts: [String: Int] = [
      "content/docs/00-introduction/01-installation.mdx": 1,
      "content/docs/00-introduction/02-quickstart.mdx": 3,
      "content/docs/02-foundations/01-messages.mdx": 1,
      "content/docs/02-foundations/02-models-and-providers.mdx": 1,
      "content/docs/02-foundations/04-schemas-and-macros.mdx": 4,
      "content/docs/03-aikit-core/01-generate-text.mdx": 3,
      "content/docs/03-aikit-core/02-stream-text.mdx": 3,
      "content/docs/03-aikit-core/03-outputs.mdx": 1,
      "content/docs/03-aikit-core/04-tools.mdx": 1,
      "content/docs/03-aikit-core/05-tool-approvals.mdx": 2,
      "content/docs/03-aikit-core/06-stop-conditions.mdx": 1,
      "content/docs/03-aikit-core/08-tool-loop-agent.mdx": 1,
      "content/docs/03-aikit-core/09-chat-session.mdx": 2,
      "content/docs/04-providers/01-openrouter.mdx": 2,
    ]

    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // AIKitDocsExamplesE2ETests.swift
      .deletingLastPathComponent() // AIKitE2ETests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // AIKitE2E
      .deletingLastPathComponent() // E2E

    func countSwiftFences(_ text: String) -> Int {
      text.components(separatedBy: "```swift\n").count - 1
    }

    var observed: [String: Int] = [:]
    for (relPath, _) in expectedCounts {
      let url = repoRoot.appendingPathComponent(relPath)
      let text = try String(contentsOf: url, encoding: .utf8)
      observed[relPath] = countSwiftFences(text)
    }

    XCTAssertEqual(observed, expectedCounts)
    XCTAssertEqual(observed.values.reduce(0, +), 26)
  }

  func testDocsQuickstartExamples_compileAndRunWithMockModel() async throws {
    _ = createOpenRouter(.init(apiKey: nil))
    _ = openrouter.chat("openai/gpt-4o-mini")

    let model = QueuedLanguageModel(generateQueue: [
      { _ in
        .init(
          content: [.text("Hello from generateText.")],
          finishReason: .stop,
          rawFinishReason: "stop"
        )
      },
    ], stream: { _ in
      makeStream([
        .streamStart(),
        .startStep(),
        .textStart(id: "t1", providerMetadata: nil),
        .textDelta(id: "t1", text: "Hello", providerMetadata: nil),
        .textDelta(id: "t1", text: " world", providerMetadata: nil),
        .textEnd(id: "t1", providerMetadata: nil),
        .finishStep(finishReason: .stop, rawFinishReason: "stop"),
        .finish(finishReason: .stop),
      ])
    })

    let ai = AIClient(model: model)
    let result = try await ai.generate("Write a haiku about Swift concurrency.")

    XCTAssertEqual(result.text, "Hello from generateText.")

    let stream = ai.stream("Write a short story in three sentences.")

    var combined = ""
    for try await delta in stream.textStream {
      combined += delta
    }
    XCTAssertEqual(combined, "Hello world")
  }

  func testDocsGenerateText_messagesInsteadOfPrompt_runs() async throws {
    let model = RecordingLanguageModel { request in
      XCTAssertEqual(request.messages.first?.role, .system)
      XCTAssertEqual(request.messages.dropFirst().first?.role, .user)
      return .init(content: [.text("ok")], finishReason: .stop, rawFinishReason: "stop")
    }

    let ai = AIClient(model: model)
    let result = try await ai.generate(messages: [
      .system("You are concise."),
      .user("Give me three names for a coffee shop."),
    ])

    XCTAssertEqual(result.text, "ok")
  }

  func testDocsToolsExample_registersAndToolLoopExecutes() async throws {
    let weather = ToolID<DocsWeatherInput, String>("weather")

    var tools = ToolRegistry()
    tools.register(
      weather,
      ToolSpec(
        title: "Weather",
        description: "Get current weather for a city.",
        inputSchema: DocsWeatherInput.schema,
        execute: { input, _ in
          .final("Sunny in \(input.city)")
        }
      )
    )

    let toolCall = ToolCall(
      toolCallID: "call-1",
      toolName: "weather",
      inputJSON: "{\"city\":\"NYC\"}",
      input: .object(["city": .string("NYC")])
    )

    let model = QueuedLanguageModel(generateQueue: [
      { request in
        XCTAssertEqual(request.tools.map(\.name), ["weather"])
        return .init(
          content: [.toolCall(toolCall)],
          finishReason: .toolCalls,
          rawFinishReason: "tool_calls"
        )
      },
      { _ in
        .init(content: [.text("Done")], finishReason: .stop, rawFinishReason: "stop")
      },
    ])

    let ai = AIClient(model: model, defaults: .init(tools: tools, maxSteps: 5))
    let result = try await ai.generate("Call the tool, then explain the result.")

    let allToolResults = result.steps.flatMap(\.toolResults)
    XCTAssertEqual(allToolResults.first?.toolName, "weather")
    XCTAssertEqual(result.text, "Done")
  }

  func testDocsToolApprovals_exampleMessageConstruction_compiles() throws {
    let request = ToolApprovalRequest(approvalID: "id-1", toolCallID: "call-1", toolCall: nil)
    let response = ToolApprovalResponse(approvalID: request.approvalID, approved: true)

    let approvalMessage = ModelMessage(
      role: .tool,
      content: [.toolApprovalResponse(response)]
    )

    XCTAssertEqual(approvalMessage.role, .tool)
  }

  func testDocsToolLoopAgent_exampleRuns() async throws {
    var tools = ToolRegistry()
    _ = tools // mirrors docs default usage; tool loop behavior is covered elsewhere

    let model = RecordingLanguageModel { _ in
      .init(content: [.text("agent ok")], finishReason: .stop, rawFinishReason: "stop")
    }

    let agent = ToolLoopAgent<Void, Output.Text>(
      model: model,
      instructions: .instructions("You are a helpful assistant."),
      tools: tools,
      stopWhen: [Stop.stepCountIs(20)],
      output: Output.text()
    )

    let result = try await agent.generate(prompt: "Plan a weekend trip.")
    XCTAssertEqual(result.text, "agent ok")
  }

  func testDocsChatStore_examplesCompile() async {
    let model = RecordingLanguageModel { _ in
      .init(content: [.text("ok")], finishReason: .stop, rawFinishReason: "stop")
    }

    #if canImport(Combine)
    await MainActor.run {
      _ = ChatStore(model: model, system: .instructions("You are helpful."))
      _ = ChatStore(remote: URL(string: "https://example.com/api/chat")!)
    }
    #endif
  }

  func testDocsOpenAIProviderSurface_compiles() {
    _ = createOpenAI(.init(apiKey: nil))
    _ = openai
  }
}
