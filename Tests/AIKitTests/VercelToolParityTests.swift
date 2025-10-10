import Testing
import Foundation
@testable import AIKit

@Suite("Vercel Tool Parity")
struct VercelToolParityTests {
    @Test("Auto tool call matches Vercel formatting")
    func testAutoSingleToolCallMatchesVercel() async throws {
        try await assertScenario(named: "auto-single-tool-call")
    }

    @Test("Multi tool handoff matches Vercel formatting")
    func testMultiToolHandoffMatchesVercel() async throws {
        try await assertScenario(named: "multi-tool-handoff")
    }

    @Test("JSON tool result matches Vercel formatting")
    func testToolJsonResultMatchesVercel() async throws {
        try await assertScenario(named: "tool-json-result")
    }

    @Test("Tool execution error parity")
    func testToolExecutionErrorMatchesVercel() async throws {
        try await assertScenario(named: "tool-execution-error")
    }

    @Test("Sequential image tool ordering aligns with Vercel")
    func testSequentialImageToolsMatchesVercel() async throws {
        try await assertScenario(named: "sequential-image-tools")
    }

    @Test("Interleaved tool calls match Vercel ordering")
    func testInterleavedImageToolsMatchesVercel() async throws {
        try await assertScenario(named: "interleaved-image-tools")
    }

    @Test("Assistant preface text stays ahead of tool call")
    func testPrefaceTextAndImageOrderingMatchesVercel() async throws {
        try await assertScenario(named: "preface-text-and-image")
    }
}

// MARK: - Assertion Helper

private func assertScenario(named scenarioName: String) async throws {
    let scenario = try VercelToolScenario.load(named: scenarioName)
    let providerResponses = scenario.makeProviderResponses()
    let provider = VercelFixtureProvider(responses: providerResponses)
    let model = provider.languageModel("vercel-fixture")
    let tools = try scenario.makeTools()
    let messages = try scenario.inputMessages()
    let toolChoice = scenario.expectedToolChoice()
    let client = AIClient()

    if scenario.vercel.error != nil {
        await #expect(throws: AIGenerationError.self) {
            _ = try await client.generateText(
                model,
                messages: messages,
                tools: tools,
                toolChoice: toolChoice,
                maxSteps: scenario.maxSteps
            )
        }
        return
    }

    let response = try await client.generateText(
        model,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
        maxSteps: scenario.maxSteps
    )

    guard let expected = scenario.vercel.result else {
        throw ScenarioError.missingExpectedResult
    }

    #expect(response.text == expected.text)
    #expect(response.finishReason.rawValue == expected.finishReason)
    #expect(response.usage.promptTokens == expected.usage.promptTokens)
    #expect(response.usage.completionTokens == expected.usage.completionTokens)
    #expect(response.usage.totalTokens == expected.usage.totalTokens)

    let messageToolLookup = makeToolNameLookup(from: response.messages)
    let comparableMessages = collapseToolMessages(try normalizeComparableMessages(
        response.messages
        .filter { $0.role != .user }
        .map { try $0.toComparableMessage(toolNameLookup: messageToolLookup) }
    ))
    let expectedMessages = collapseToolMessages(try normalizeComparableMessages(scenario.expectedComparableMessages()))
    #expect(comparableMessages == expectedMessages)

    let expectedSteps = try normalizeComparableSteps(scenario.expectedComparableSteps())
    if let steps = response.steps {
        let comparableSteps = try normalizeComparableSteps(normalizedComparableSteps(from: steps))
        #expect(comparableSteps == expectedSteps)
    } else {
        #expect(expectedSteps.isEmpty)
    }

    #expect(provider.didConsumeAllResponses)
}
