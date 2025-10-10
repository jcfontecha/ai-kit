import Testing
import Foundation
@testable import AIKit

@Suite("Real Vercel vs AIKit (OpenAI)")
struct RealVercelToolParityTests {
    @Test("Auto tool call parity (OpenAI live)")
    func testAutoSingleToolCall() async throws {
        try await assertLiveScenario(named: "auto-single-tool-call")
    }

    @Test("Multi tool handoff parity (OpenAI live)")
    func testMultiToolHandoff() async throws {
        try await assertLiveScenario(named: "multi-tool-handoff")
    }

    @Test("JSON tool result parity (OpenAI live)")
    func testToolJsonResult() async throws {
        try await assertLiveScenario(named: "tool-json-result")
    }

    @Test("Sequential image tools parity (OpenAI live)")
    func testSequentialImageTools() async throws {
        try await assertLiveScenario(named: "sequential-image-tools")
    }

    @Test("Interleaved image tools parity (OpenAI live)")
    func testInterleavedImageTools() async throws {
        try await assertLiveScenario(named: "interleaved-image-tools")
    }

    @Test("Preface text with image parity (OpenAI live)")
    func testPrefaceTextAndImage() async throws {
        try await assertLiveScenario(named: "preface-text-and-image")
    }
}

// MARK: - Live Parity Assertion

private func assertLiveScenario(named scenarioName: String) async throws {
    let configResult = Result { try LiveScenarioConfig.load() }
    guard case .success(let config) = configResult else {
        if case .failure(let error) = configResult {
            Issue.record("Skipping live parity test due to missing configuration: \(error)")
        }
        return
    }

    let payloadResult = Result { try runLiveScenarioPayload(named: scenarioName, apiKey: config.openAIKey) }
    guard case .success(let payload) = payloadResult else {
        if case .failure(let error) = payloadResult,
           let execError = error as? LiveExecutionError,
           execError.isTimeout {
            print("Skipping scenario \(scenarioName) due to request timeout")
            return
        } else if case .failure(let error) = payloadResult {
            throw error
        } else {
            return
        }
    }

    guard let vercelResult = payload.vercel.result else {
        throw ScenarioError.missingExpectedResult
    }

    let messages = try VercelToolScenario.buildMessages(for: payload.name, config: payload.config)
    let tools = try makeTools(
        for: payload.name,
        schemas: payload.toolSchemas,
        executions: payload.toolExecutions,
        steps: payload.vercel.result?.steps,
        errorDescriptor: payload.vercel.error
    )
    let toolChoice = toolChoice(from: payload.toolChoice)

    let provider = OpenAIProvider(apiKey: config.openAIKey)
    var model = provider.languageModel(payload.model)
    let seedValue: Int = {
        if let seedString = ProcessInfo.processInfo.environment["VERCEL_PARITY_SEED"],
           let parsed = Int(seedString) {
            return parsed
        }
        return 42
    }()
    let seededConfiguration = model.configuration.seed(seedValue)
    model = LanguageModel(provider: model.provider, modelId: model.modelId, configuration: seededConfiguration)
    model = model.temperature(0)

    let client = AIClient()
    let aikitResponse = try await client.generateText(
        model,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
        maxSteps: payload.maxSteps
    )


    // Comparable representations
    let vercelComparableMessages = collapseToolMessages(try normalizeComparableMessages(
        vercelResult.response?.messages.map { try $0.toComparableMessage() } ?? []
    ))
    let aikitComparableMessages = collapseToolMessages(try normalizeComparableMessages(
        aikitResponse.messages
            .filter { $0.role != .user }
            .map { try $0.toComparableMessage(toolNameLookup: makeToolNameLookup(from: aikitResponse.messages)) }
    ))
    let aikitCallSummaries = toolCallSummaries(from: aikitComparableMessages)
    let vercelCallSummaries = toolCallSummaries(from: vercelComparableMessages)
    #expect(aikitCallSummaries.map { $0.toolName } == vercelCallSummaries.map { $0.toolName })

    let aikitResultSummaries = toolResultSummaries(from: aikitComparableMessages)
    let vercelResultSummaries = toolResultSummaries(from: vercelComparableMessages)
    #expect(aikitResultSummaries.map { $0.toolName } == vercelResultSummaries.map { $0.toolName })

    var aikitComparableSteps: [ComparableStep]
    if let steps = aikitResponse.steps {
        aikitComparableSteps = try normalizeComparableSteps(normalizedComparableSteps(from: steps))
    } else {
        aikitComparableSteps = []
    }
    var vercelComparableSteps = try normalizeComparableSteps(
        payload.vercel.result?.steps?.map { try $0.toComparableStep() } ?? []
    )
    aikitComparableSteps = mergeComparableToolCallSteps(aikitComparableSteps)
    vercelComparableSteps = mergeComparableToolCallSteps(vercelComparableSteps)
    if payload.name == "preface-text-and-image" {
        aikitComparableSteps = collapseTrailingTextOnlyToolResult(aikitComparableSteps)
        vercelComparableSteps = collapseTrailingTextOnlyToolResult(vercelComparableSteps)
    }
    if payload.name == "preface-text-and-image" {
        if ProcessInfo.processInfo.environment["VERCEL_PARITY_DEBUG"] == "1" {
            print("AIKit comparable steps:", aikitComparableSteps)
            print("Vercel comparable steps:", vercelComparableSteps)
        } else {
            print("AIKit step types:", aikitComparableSteps.map { $0.stepType })
            print("Vercel step types:", vercelComparableSteps.map { $0.stepType })
        }
    }
    #expect(aikitComparableSteps.map { $0.stepType } == vercelComparableSteps.map { $0.stepType })
    #expect(aikitComparableSteps.count == vercelComparableSteps.count)

    let aikitAssistantTexts = finalAssistantTexts(from: aikitComparableMessages)
    let vercelAssistantTexts = finalAssistantTexts(from: vercelComparableMessages)
    #expect(!aikitAssistantTexts.isEmpty)
    #expect(!vercelAssistantTexts.isEmpty)
    if let aikitFinal = aikitAssistantTexts.last, let vercelFinal = vercelAssistantTexts.last {
        print("AIKit final response: \(aikitFinal)")
        print("Vercel final response: \(vercelFinal)")
    }

    let usage = vercelResult.usage
    if aikitResponse.usage.promptTokens != usage.promptTokens || aikitResponse.usage.completionTokens != usage.completionTokens {
        print(
            "Token usage differed. AIKit prompt=\(aikitResponse.usage.promptTokens) completion=\(aikitResponse.usage.completionTokens); Vercel prompt=\(usage.promptTokens) completion=\(usage.completionTokens)"
        )
    }
}

// MARK: - Helpers

private func collapseTrailingTextOnlyToolResult(_ steps: [ComparableStep]) -> [ComparableStep] {
    guard let last = steps.last,
          last.stepType == "tool-result",
          last.toolCallIds.isEmpty,
          last.toolResults.isEmpty else {
        return steps
    }
    return Array(steps.dropLast())
}

private struct LiveScenarioConfig {
    let openAIKey: String

    static func load() throws -> LiveScenarioConfig {
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            return LiveScenarioConfig(openAIKey: envKey)
        }
        let configURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Config.plist")
        guard let data = try? Data(contentsOf: configURL) else {
            throw LiveConfigError.missingConfig("Config.plist not found at \(configURL.path)")
        }
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw LiveConfigError.invalidConfig("Unable to parse Config.plist")
        }
        guard let apiKey = plist["OPENAI_API_KEY"] as? String, !apiKey.isEmpty else {
            throw LiveConfigError.missingKey("OPENAI_API_KEY not found or empty in Config.plist")
        }
        return LiveScenarioConfig(openAIKey: apiKey)
    }
}

private enum LiveConfigError: Error {
    case missingConfig(String)
    case invalidConfig(String)
    case missingKey(String)
}

private struct LiveScenarioPayload: Decodable {
    let name: String
    let model: String
    let config: VercelToolScenario.ScenarioConfig
    let maxSteps: Int
    let toolChoice: String?
    let toolSchemas: [VercelToolScenario.ToolSchema]
    let toolExecutions: [VercelToolScenario.ToolExecution]
    let vercel: VercelToolScenario.VercelOutcome
}

private func runLiveScenarioPayload(named scenario: String, apiKey: String) throws -> LiveScenarioPayload {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "tools/vercel-comparison/run-live-scenario.mjs", scenario]
    var environment = ProcessInfo.processInfo.environment
    environment["OPENAI_API_KEY"] = apiKey
    process.environment = environment

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw LiveExecutionError.processFailed("Live scenario runner failed: \(errorOutput)")
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(LiveScenarioPayload.self, from: data)
}

private enum LiveExecutionError: Error {
    case processFailed(String)

    var isTimeout: Bool {
        switch self {
        case .processFailed(let message):
            return message.contains("timed out")
        }
    }
}

private func makeTools(
    for scenarioName: String,
    schemas: [VercelToolScenario.ToolSchema],
    executions: [VercelToolScenario.ToolExecution],
    steps: [VercelToolScenario.VercelStep]?,
    errorDescriptor: VercelToolScenario.VercelError?
) throws -> [Tool] {
    let recordedResults = try VercelToolScenario.buildRecordedToolResults(
        executions: executions,
        steps: steps
    )

    return try schemas.map { schema in
        let jsonSchema = try JSONSchemaConverter().convert(schema.schema)
        let function = ToolFunction(
            name: schema.name,
            description: schema.description,
            parameters: jsonSchema
        )
        let execute: (@Sendable (ToolCall) async throws -> ToolResult)? = { toolCall in
            try await VercelToolScenario.executeTool(
                scenarioName: scenarioName,
                toolName: schema.name,
                toolCall: toolCall,
                errorDescriptor: errorDescriptor,
                recordedResults: recordedResults
            )
        }
        return Tool(function: function, execute: execute)
    }
}

private func toolChoice(from value: String?) -> ToolChoice? {
    guard let value else { return nil }
    switch value {
    case "auto": return .auto
    case "required": return .required
    case "none": return ToolChoice.none
    default: return .specific(value)
    }
}
