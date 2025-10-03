import Foundation
@testable import AIKit

// MARK: - Scenario Loading

struct VercelToolScenario: Decodable, Sendable {
    let name: String
    let description: String
    let config: ScenarioConfig
    let maxSteps: Int
    let toolChoice: String?
    let toolSchemas: [ToolSchema]
    let modelResponses: [ModelResponse]
    let recordedModelCalls: [RecordedCall]
    let toolExecutions: [ToolExecution]
    let vercel: VercelOutcome

    // MARK: Loading

    static func load(named scenarioName: String, filePath: StaticString = #filePath) throws -> VercelToolScenario {
        let fileURL = URL(fileURLWithPath: String(describing: filePath))
            .deletingLastPathComponent() // .../AIKitTests/VercelParity
            .appendingPathComponent("../Fixtures/VercelToolParity/\(scenarioName).json")
            .standardized

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VercelToolScenario.self, from: data)
    }

    // MARK: Transforms

    func makeProviderResponses(dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()) -> [ProviderResponse] {
        if let steps = vercel.result?.steps, !steps.isEmpty {
            return Self.providerResponses(from: steps, usage: vercel.result?.usage)
        }

        return modelResponses.map { response in
            let toolCalls = response.toolCalls.map { call -> ToolCall in
                let function = ToolCallFunction(name: call.toolName, arguments: call.canonicalArguments)
                return ToolCall(id: call.toolCallId, type: .function, function: function, timestamp: Date())
            }

            let usage = Usage(
                promptTokens: response.usage.promptTokens,
                completionTokens: response.usage.completionTokens,
                totalTokens: response.usage.totalTokens
            )

            let finishReason = FinishReason(rawValue: response.finishReason) ?? .unknown
            let timestampString = response.response?.timestamp
            let timestamp = timestampString.flatMap { dateFormatter.date(from: $0) } ?? Date()

            return ProviderResponse(
                content: response.text,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls,
                usage: usage,
                finishReason: finishReason,
                responseId: response.response?.id,
                timestamp: timestamp,
                providerMetadata: [:]
            )
        }
    }

    private static func providerResponses(from steps: [VercelStep], usage: UsageSnapshot?) -> [ProviderResponse] {
        let aggregateUsage = Usage(
            promptTokens: usage?.promptTokens ?? 0,
            completionTokens: usage?.completionTokens ?? 0,
            totalTokens: usage?.totalTokens ?? ((usage?.promptTokens ?? 0) + (usage?.completionTokens ?? 0)),
            promptCost: nil,
            completionCost: nil,
            totalCost: nil,
            currency: nil,
            details: nil
        )

        let zeroUsage = Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0, promptCost: nil, completionCost: nil, totalCost: nil, currency: nil, details: nil)

        let relevant = steps.enumerated().filter { _, step in
            let hasToolCalls = (step.toolCalls?.isEmpty == false)
            let hasFinalText = (step.text?.isEmpty == false) && (step.toolCalls?.isEmpty ?? true)
            return hasToolCalls || hasFinalText
        }

        return relevant.enumerated().map { position, element in
            let step = element.element

            let toolCalls = step.toolCalls?.map { call in
                let function = ToolCallFunction(name: call.toolName, arguments: call.canonicalArguments)
                return ToolCall(id: call.toolCallId, type: .function, function: function, timestamp: Date())
            }

            let finishReason: FinishReason
            if let toolCalls, !toolCalls.isEmpty {
                finishReason = .toolCalls
            } else {
                finishReason = .stop
            }

            let stepUsage = position == 0 ? aggregateUsage : zeroUsage

            return ProviderResponse(
                content: step.text ?? "",
                toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls,
                usage: stepUsage,
                finishReason: finishReason,
                providerMetadata: [:]
            )
        }
    }

    func makeTools() throws -> [Tool] {
        let converter = JSONSchemaConverter()
        let recordedResults = try recordedToolResults()
        return try toolSchemas.map { schema in
            let jsonSchema = try converter.convert(schema.schema)
            let function = ToolFunction(
                name: schema.name,
                description: schema.description,
                parameters: jsonSchema
            )

            let scenarioName = self.name
            let toolName = schema.name
            let errorDescriptor = self.vercel.error
            let recordedLookup = recordedResults
            let executeClosure: (@Sendable (ToolCall) async throws -> ToolResult)? = { toolCall in
                try await Self.executeTool(
                    scenarioName: scenarioName,
                    toolName: toolName,
                    toolCall: toolCall,
                    errorDescriptor: errorDescriptor,
                    recordedResults: recordedLookup
                )
            }

            return Tool(function: function, execute: executeClosure)
        }
    }

    static func buildMessages(for scenarioName: String, config: ScenarioConfig) throws -> [Message] {
        switch config.type {
        case "messages":
            guard let messageList = config.messages else {
                throw ScenarioError.unsupportedInitialContent("Missing messages for scenario \(scenarioName)")
            }
            return try messageList.map { item in
                switch item.role {
                case "system":
                    return Message(role: .system, content: try item.makeContents())
                case "user":
                    return Message(role: .user, content: try item.makeContents())
                default:
                    throw ScenarioError.unsupportedInitialRole(item.role)
                }
            }
        case "prompt":
            guard let prompt = config.prompt else {
                throw ScenarioError.unsupportedInitialContent("Missing prompt string for scenario \(scenarioName)")
            }
            return [Message(role: .user, content: [.text(prompt)])]
        default:
            throw ScenarioError.unsupportedInitialContent("Unsupported config type: \(config.type)")
        }
    }

    static func executeTool(
        scenarioName: String,
        toolName: String,
        toolCall: ToolCall,
        errorDescriptor: VercelError?,
        recordedResults: [String: ToolResult]
    ) async throws -> ToolResult {
        if let errorDescriptor, errorDescriptor.toolCallId == toolCall.id {
            let underlying = ToolExecutionFixtureError(
                message: errorDescriptor.message,
                code: errorDescriptor.cause?.code
            )
            throw AIGenerationError.toolExecutionError(
                toolName: errorDescriptor.toolName,
                toolArgs: errorDescriptor.toolArgsCanonical,
                toolCallId: errorDescriptor.toolCallId,
                cause: underlying
            )
        }

        let parsedArgs = toolCall.function.parsedArguments ?? [:]

        if let recorded = recordedResults[toolCall.id] {
            return ToolResult(
                toolCallId: toolCall.id,
                result: recorded.result,
                timestamp: Date(),
                executionTime: recorded.executionTime,
                isError: recorded.isError,
                metadata: recorded.metadata
            )
        }

        return try fallbackToolResult(
            scenarioName: scenarioName,
            toolName: toolName,
            toolCall: toolCall,
            parsedArgs: parsedArgs
        )
    }

    private static func fallbackToolResult(
        scenarioName: String,
        toolName: String,
        toolCall: ToolCall,
        parsedArgs: [String: Any]
    ) throws -> ToolResult {
        
        switch (scenarioName, toolName) {
        case ("auto-single-tool-call", "get_weather"):
            let location = (parsedArgs["location"] as? String) ?? "Unknown"
            let unit = (parsedArgs["unit"] as? String) ?? "fahrenheit"
            let suffix = unit.lowercased() == "celsius" ? "C" : "F"
            let text = "Weather in \(location): 72°\(suffix), Sunny"
            return ToolResult(toolCallId: toolCall.id, result: .text(text))

        case ("multi-tool-handoff", "search_notes"):
            let summary = "Kyoto in May: light showers expected in afternoons."
            let json: [String: Any] = [
                "hits": [
                    [
                        "noteId": "note-kyoto-2023",
                        "summary": summary
                    ]
                ]
            ]
            return ToolResult(toolCallId: toolCall.id, result: .json(try jsonData(json)))

        case ("multi-tool-handoff", "get_weather"):
            let location = (parsedArgs["location"] as? String) ?? "Kyoto, Japan"
            let timeframe = (parsedArgs["timeframe"] as? String) ?? "week"
            let json: [String: Any] = [
                "location": location,
                "timeframe": timeframe,
                "forecast": "Mixed clouds with occasional showers. Pack a light rain jacket."
            ]
            return ToolResult(toolCallId: toolCall.id, result: .json(try jsonData(json)))

        case ("tool-json-result", "plan_menu"):
            let diet = (parsedArgs["diet"] as? String) ?? "vegan"
            let servings = (parsedArgs["servings"] as? Int) ?? 4
            let cauliflowerQuantity = max(1.0, ceil(Double(servings) / 2.0))
            let quinoaQuantity = max(0.5, ceil(Double(servings) * 0.75 * 10.0) / 10.0)
            let shoppingList: [[String: Any]] = [
                ["item": "Cauliflower heads", "quantity": cauliflowerQuantity],
                ["item": "Quinoa (cups)", "quantity": quinoaQuantity],
                ["item": "Fresh herbs bundle", "quantity": 1]
            ]
            let json: [String: Any] = [
                "diet": diet,
                "servings": servings,
                "courses": [
                    [
                        "name": "Roasted Cauliflower Steak",
                        "ingredients": ["cauliflower", "olive oil", "smoked paprika", "salt"]
                    ],
                    [
                        "name": "Quinoa Salad",
                        "ingredients": ["quinoa", "cherry tomatoes", "cucumber", "lemon"]
                    ]
                ],
                "shoppingList": shoppingList
            ]
            return ToolResult(toolCallId: toolCall.id, result: .json(try jsonData(json)))

        case ("sequential-image-tools", "generate_and_show_image"),
             ("interleaved-image-tools", "generate_and_show_image"):
            let prompt = (parsedArgs["prompt"] as? String) ?? "image"
            let attachment: String
            if scenarioName == "sequential-image-tools" {
                if toolCall.id.contains("call-img-1") || prompt.lowercased().contains("dog") {
                    attachment = "attachment_dog_image"
                } else {
                    attachment = "attachment_cat_image"
                }
            } else {
                if toolCall.id.contains("sunrise") || prompt.lowercased().contains("sunrise") {
                    attachment = "attachment_sunrise_image"
                } else {
                    attachment = "attachment_sunset_image"
                }
            }

            let payload: [String: Any] = [
                "attachments": [attachment],
                "success": true,
                "prompt": prompt
            ]
            return ToolResult(toolCallId: toolCall.id, result: .json(try jsonData(payload)))

        case ("tool-execution-error", "get_migration_status"):
            let jobId = (parsedArgs["jobId"] as? String) ?? "UNKNOWN"
            if jobId == "JOB-77" {
                let underlying = ToolExecutionFixtureError(
                    message: "Migration job timed out contacting shard-3",
                    code: "ETIMEDOUT"
                )
                throw AIGenerationError.toolExecutionError(
                    toolName: toolName,
                    toolArgs: toolCall.function.arguments,
                    toolCallId: toolCall.id,
                    cause: underlying
                )
            }
            let text = "Job \(jobId) completed successfully."
            return ToolResult(toolCallId: toolCall.id, result: .text(text))

        default:
            throw ScenarioError.unsupportedToolExecution(scenarioName: scenarioName, toolName: toolName)
        }
    }

    private func recordedToolResults() throws -> [String: ToolResult] {
        try Self.buildRecordedToolResults(
            executions: toolExecutions,
            steps: vercel.result?.steps
        )
    }

    static func buildRecordedToolResults(
        executions: [ToolExecution],
        steps: [VercelStep]?
    ) throws -> [String: ToolResult] {
        var lookup: [String: ToolResult] = [:]

        for execution in executions {
            guard let callId = execution.callId else { continue }
            lookup[callId] = try execution.makeToolResult(toolCallId: callId)
        }

        if let steps {
            for step in steps {
                for result in step.toolResults ?? [] {
                    lookup[result.toolCallId] = try result.toToolResult()
                }
            }
        }

        return lookup
    }

    func inputMessages() throws -> [Message] {
        try Self.buildMessages(for: name, config: config)
    }

    func expectedToolChoice() -> ToolChoice? {
        guard let choice = toolChoice else { return nil }
        switch choice {
        case "auto": return .auto
        case "required": return .required
        case "none": return .some(.none)
        default: return .specific(choice)
        }
    }

    func expectedComparableMessages() throws -> [ComparableMessage] {
        guard let response = vercel.result?.response else {
            throw ScenarioError.missingExpectedResult
        }
        return try response.messages.map { try $0.toComparableMessage() }
    }

    func expectedComparableSteps() throws -> [ComparableStep] {
        guard let steps = vercel.result?.steps else { return [] }
        return try steps.map { try $0.toComparableStep() }
    }
}

// MARK: - Scenario Model

extension VercelToolScenario {
    struct ScenarioConfig: Decodable, Sendable {
        let type: String
        let messages: [ScenarioMessage]?
        let prompt: String?
    }

    struct ScenarioMessage: Decodable, Sendable {
        let role: String
        let content: [ScenarioContent]

        func makeContents() throws -> [MessageContent] {
            try content.map { try $0.toMessageContent() }
        }
    }

    struct ScenarioContent: Decodable, Sendable {
        let type: String
        let text: String?

        func toMessageContent() throws -> MessageContent {
            switch type {
            case "text":
                return .text(text ?? "")
            default:
                throw ScenarioError.unsupportedInitialContent(type)
            }
        }
    }

    struct ToolSchema: Decodable, Sendable {
        let name: String
        let description: String
        let schema: RawSchema
    }

    struct ModelResponse: Decodable, Sendable {
        let text: String
        let finishReason: String
        let toolCalls: [RawToolCall]
        let usage: UsageSnapshot
        let response: ResponseMetadata?
        let rawCall: RawCall?
    }

    struct RawToolCall: Decodable, Sendable {
        let toolCallId: String
        let toolName: String
        let arguments: JSONValue?
        let rawArguments: String?

        private enum CodingKeys: String, CodingKey {
            case toolCallId
            case toolName
            case arguments
            case args
            case rawArguments
        }

        init(toolCallId: String, toolName: String, arguments: JSONValue?, rawArguments: String?) {
            self.toolCallId = toolCallId
            self.toolName = toolName
            self.arguments = arguments
            self.rawArguments = rawArguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.toolCallId = try container.decode(String.self, forKey: .toolCallId)
            self.toolName = try container.decode(String.self, forKey: .toolName)
            self.rawArguments = try container.decodeIfPresent(String.self, forKey: .rawArguments)
            if let value = try container.decodeIfPresent(JSONValue.self, forKey: .arguments) {
                self.arguments = value
            } else if let value = try container.decodeIfPresent(JSONValue.self, forKey: .args) {
                self.arguments = value
            } else {
                self.arguments = nil
            }
        }

        var canonicalArguments: String {
            if let rawArguments {
                return rawArguments
            }
            return (try? arguments?.canonicalJSONString()) ?? "{}"
        }
    }

    struct UsageSnapshot: Decodable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }

    struct ResponseMetadata: Decodable, Sendable {
        let id: String
        let timestamp: String
        let modelId: String
    }

    struct RawCall: Decodable, Sendable {
        let rawPrompt: String?
        let rawSettings: [String: JSONValue]?
    }

    struct RecordedCall: Decodable, Sendable {
        let step: Int
        let mode: JSONValue
        let prompt: [ScenarioMessage]
    }

    struct ToolExecution: Decodable, Sendable {
        let toolName: String
        let callId: String?
        let args: [String: JSONValue]
        let result: ToolExecutionResult?

        func makeToolResult(toolCallId: String) throws -> ToolResult {
            guard let result else {
                return ToolResult(
                    toolCallId: toolCallId,
                    result: .text(""),
                    timestamp: Date()
                )
            }

            switch result.type {
            case "text":
                return ToolResult(
                    toolCallId: toolCallId,
                    result: .text(result.value?.stringValue ?? ""),
                    timestamp: Date()
                )
            case "json":
                guard let json = result.value?.toJSONObject() else {
                    throw ScenarioError.invalidJSONResult
                }
                let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
                return ToolResult(
                    toolCallId: toolCallId,
                    result: .json(data),
                    timestamp: Date()
                )
            default:
                return ToolResult(
                    toolCallId: toolCallId,
                    result: .text(result.value?.stringValue ?? ""),
                    timestamp: Date()
                )
            }
        }
    }

    struct ToolExecutionResult: Decodable, Sendable {
        let type: String
        let value: JSONValue?
    }

    struct VercelOutcome: Decodable, Sendable {
        let result: VercelSuccess?
        let error: VercelError?
    }

    struct VercelSuccess: Decodable, Sendable {
        let text: String
        let files: [JSONValue]
        let reasoningDetails: [JSONValue]
        let toolCalls: [JSONValue]
        let toolResults: [JSONValue]
        let finishReason: String
        let usage: UsageSnapshot
        let response: VercelResponse?
        let steps: [VercelStep]?
    }

    struct VercelResponse: Decodable, Sendable {
        let id: String?
        let timestamp: String?
        let modelId: String?
        let messages: [VercelMessage]
    }

    struct VercelMessage: Decodable, Sendable {
        let role: String
        let content: [VercelContent]

        func toComparableMessage() throws -> ComparableMessage {
            let comparable = try content.map { try $0.toComparableContent() }
            return ComparableMessage(role: role, contents: comparable)
        }
    }

    struct VercelContent: Decodable, Sendable {
        let type: String
        let text: String?
        let toolCallId: String?
        let toolName: String?
        let args: JSONValue?
        let result: JSONValue?

        func toComparableContent() throws -> ComparableContent {
            switch type {
            case "text":
                return .text(text ?? "")
            case "tool-call":
                let canonicalArgs = try args?.canonicalJSONString() ?? "{}"
                return .toolCall(toolName: toolName ?? "", callId: toolCallId ?? "", canonicalArguments: canonicalArgs)
            case "tool-result":
                if let result, result.isJSONObject {
                    return .toolResult(
                        toolName: toolName ?? "",
                        callId: toolCallId ?? "",
                        canonicalResult: try result.canonicalJSONString()
                    )
                } else {
                    return .toolResult(
                        toolName: toolName ?? "",
                        callId: toolCallId ?? "",
                        canonicalResult: result?.stringValue ?? ""
                    )
                }
            default:
                throw ScenarioError.unsupportedVercelContent(type)
            }
        }
    }

    struct VercelStep: Decodable, Sendable {
        let stepType: String
        let toolCalls: [RawToolCall]?
        let toolResults: [VercelStepToolResult]?
        let text: String?

        func toComparableStep() throws -> ComparableStep {
            let callIds = toolCalls?.map { $0.toolCallId } ?? []
            let results = try toolResults?.map { try $0.toComparableContent() } ?? []
            return ComparableStep(stepType: stepType, toolCallIds: callIds, toolResults: results, text: text)
        }
    }

    struct VercelStepToolResult: Decodable, Sendable {
        let toolCallId: String
        let toolName: String
        let result: JSONValue

        func toComparableContent() throws -> ComparableContent {
            if result.isJSONObject {
                return .toolResult(
                    toolName: toolName,
                    callId: toolCallId,
                    canonicalResult: try result.canonicalJSONString()
                )
            } else {
                return .toolResult(
                    toolName: toolName,
                    callId: toolCallId,
                    canonicalResult: result.stringValue ?? ""
                )
            }
        }

        func toToolResult() throws -> ToolResult {
            switch result {
            case .object, .array:
                guard let jsonObject = result.toJSONObject() else {
                    throw ScenarioError.invalidJSONResult
                }
                let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
                return ToolResult(toolCallId: toolCallId, result: .json(data))
            case .string(let value):
                return ToolResult(toolCallId: toolCallId, result: .text(value))
            case .number(let value):
                return ToolResult(toolCallId: toolCallId, result: .text(String(value)))
            case .bool(let value):
                return ToolResult(toolCallId: toolCallId, result: .text(value ? "true" : "false"))
            case .null:
                return ToolResult(toolCallId: toolCallId, result: .text(""))
            }
        }
    }

    struct VercelError: Decodable, Sendable {
        let name: String
        let message: String
        let stack: String?
        let cause: ErrorCause?
        let toolArgs: JSONValue?
        let toolName: String
        let toolCallId: String

        var toolArgsCanonical: String {
            (try? toolArgs?.canonicalJSONString()) ?? "{}"
        }

        struct ErrorCause: Decodable {
            let code: String?
        }
    }
}

// MARK: - Comparable Helpers

struct ComparableMessage: Equatable {
    let role: String
    let contents: [ComparableContent]
}

enum ComparableContent: Equatable {
    case text(String)
    case toolCall(toolName: String, callId: String, canonicalArguments: String)
    case toolResult(toolName: String?, callId: String, canonicalResult: String)
}

struct ComparableStep: Equatable {
    let stepType: String
    let toolCallIds: [String]
    let toolResults: [ComparableContent]
    let text: String?
}

// MARK: - JSON Utilities

enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    var isJSONObject: Bool {
        if case .object = self { return true }
        return false
    }

    func toJSONObject() -> Any? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value.rounded() == value { return Int(value) }
            return value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let array):
            return array.compactMap { $0.toJSONObject() }
        case .object(let dict):
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.toJSONObject()
            }
            return result
        }
    }

    func canonicalJSONString() throws -> String {
        guard let jsonObject = toJSONObject() else {
            return "null"
        }
        if let string = jsonObject as? String {
            if let data = try? JSONSerialization.data(withJSONObject: ["value": string], options: [.sortedKeys]),
               let encoded = String(data: data, encoding: .utf8) {
                // extract value field without quotes duplication
                if let range = encoded.range(of: ":\"") {
                    let endIndex = encoded.index(before: encoded.endIndex)
                    return String(encoded[encoded.index(range.upperBound, offsetBy: 0)..<endIndex])
                }
            }
            return "\(string)"
        }
        let options: JSONSerialization.WritingOptions = [.sortedKeys]
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: options)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Schema Conversion

struct RawSchema: Decodable, Sendable {
    let type: String
    let description: String?
    let properties: [String: RawSchema]?
    let required: [String]?
    let enumValues: [String]?
    let additionalProperties: RawAdditionalProperties?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case enumValues = "enum"
        case additionalProperties
    }
}

indirect enum RawAdditionalProperties: Decodable, Sendable {
    case bool(Bool)
    case schema(RawSchema)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else {
            let schema = try container.decode(RawSchema.self)
            self = .schema(schema)
        }
    }
}

struct JSONSchemaConverter: Sendable {
    func convert(_ raw: RawSchema) throws -> JSONSchema {
        guard let schemaType = JSONSchemaType(rawValue: raw.type) else {
            throw ScenarioError.unsupportedSchemaType(raw.type)
        }

        let properties = try raw.properties?.mapValues { try convert($0) }
        let enumValues = raw.enumValues?.map { JSONSchemaValue.string($0) }

        let additionalProps: AdditionalProperties?
        if let additional = raw.additionalProperties {
            switch additional {
            case .bool(let value):
                additionalProps = .boolean(value)
            case .schema(let nested):
                additionalProps = .schema(try convert(nested))
            }
        } else {
            additionalProps = nil
        }

        return .definition(
            SchemaDefinition(
                type: schemaType,
                properties: properties,
                required: raw.required,
                enum: enumValues,
                description: raw.description,
                additionalProperties: additionalProps
            )
        )
    }
}

// MARK: - Errors

enum ScenarioError: Error, Sendable {
    case unsupportedInitialRole(String)
    case unsupportedInitialContent(String)
    case unsupportedSchemaType(String)
    case unsupportedVercelContent(String)
    case missingExpectedResult
    case invalidJSONResult
    case unsupportedToolExecution(scenarioName: String, toolName: String)
}

struct ToolExecutionFixtureError: Error, Sendable {
    let message: String
    let code: String?
}

private func jsonData(_ object: Any) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return data
}

extension ToolExecutionFixtureError: LocalizedError {
    var errorDescription: String? { message }
}

// MARK: - Convenience Extensions
