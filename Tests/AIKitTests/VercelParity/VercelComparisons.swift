import Foundation
@testable import AIKit

// MARK: - Canonical Helpers

func canonicalJSONString(from string: String) throws -> String {
    guard let data = string.data(using: .utf8) else {
        return string
    }
    let object = try JSONSerialization.jsonObject(with: data)
    let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: canonical, encoding: .utf8) ?? string
}

func makeToolNameLookup(from steps: [GenerationStep]?) -> [String: String] {
    var lookup: [String: String] = [:]
    steps?.forEach { step in
        step.toolCalls?.forEach { call in
            lookup[call.id] = call.function.name
        }
    }
    return lookup
}

func makeToolNameLookup(from messages: [Message]) -> [String: String] {
    var lookup: [String: String] = [:]
    for message in messages {
        for content in message.content {
            if case .toolCall(let call) = content {
                lookup[call.id] = call.function.name
            }
        }
    }
    return lookup
}

func normalizedComparableSteps(from steps: [GenerationStep]) throws -> [ComparableStep] {
    let lookup = makeToolNameLookup(from: steps)

    return try steps.enumerated().map { index, step in
        let toolResults = try step.toolResults?.map { try $0.toComparableContent(toolName: lookup[$0.toolCallId]) } ?? []
        let normalizedType: String
        switch step.stepType {
        case .toolCall, .toolResult:
            normalizedType = index == 0 ? "initial" : "tool-result"
        case .initial:
            normalizedType = "initial"
        case .continue:
            normalizedType = "tool-result"
        case .reasoning, .validation:
            normalizedType = step.stepType.rawValue
        @unknown default:
            normalizedType = step.stepType.rawValue
        }
        return ComparableStep(
            stepType: normalizedType,
            toolCallIds: step.toolCalls?.map { $0.id } ?? [],
            toolResults: toolResults,
            text: step.concatenatedText()
        )
    }
}

extension GenerationStep {
    func concatenatedText() -> String? {
        let segments = messages?
            .flatMap { $0.content }
            .compactMap { content -> String? in
                if case .text(let value) = content {
                    return value
                }
                return nil
            }

        guard let segments, !segments.isEmpty else { return nil }
        return segments.joined(separator: " ")
    }
}

extension Message {
    func toComparableMessage(toolNameLookup: [String: String]) throws -> ComparableMessage {
        let contents = try content.map { try $0.toComparableContent(toolNameLookup: toolNameLookup) }
        return ComparableMessage(role: role.rawValue, contents: contents)
    }
}

extension MessageContent {
    func toComparableContent(toolNameLookup: [String: String]) throws -> ComparableContent {
        switch self {
        case .text(let text):
            return .text(text)
        case .toolCall(let call):
            let canonical = try canonicalJSONString(from: call.function.arguments)
            return .toolCall(toolName: call.function.name, callId: call.id, canonicalArguments: canonical)
        case .toolResult(let result):
            let toolName = toolNameLookup[result.toolCallId]
            return try result.toComparableContent(toolName: toolName)
        default:
            throw ScenarioError.unsupportedVercelContent("Unsupported message content")
        }
    }
}

// MARK: - ID Normalization

func normalizeComparableMessages(_ messages: [ComparableMessage]) -> [ComparableMessage] {
    var mapping: [String: String] = [:]
    var counter = 0
    func mapId(_ id: String) -> String {
        if let existing = mapping[id] {
            return existing
        }
        let newId = "call_\(counter)"
        mapping[id] = newId
        counter += 1
        return newId
    }

    return messages.map { message in
        let contents = message.contents.map { content -> ComparableContent in
            switch content {
            case .toolCall(let toolName, let callId, let canonicalArguments):
                return .toolCall(toolName: toolName, callId: mapId(callId), canonicalArguments: canonicalArguments)
            case .toolResult(let toolName, let callId, let canonicalResult):
                return .toolResult(toolName: toolName, callId: mapId(callId), canonicalResult: canonicalResult)
            case .text:
                return content
            }
        }
        return ComparableMessage(role: message.role, contents: contents)
    }
}

func collapseToolMessages(_ messages: [ComparableMessage]) -> [ComparableMessage] {
    var collapsed: [ComparableMessage] = []
    for message in messages {
        if let last = collapsed.last, last.role == "tool", message.role == "tool" {
            var merged = last
            merged = ComparableMessage(role: last.role, contents: last.contents + message.contents)
            collapsed[collapsed.count - 1] = merged
        } else {
            collapsed.append(message)
        }
    }
    return collapsed
}

func normalizeComparableSteps(_ steps: [ComparableStep]) -> [ComparableStep] {
    var mapping: [String: String] = [:]
    var counter = 0
    func mapId(_ id: String) -> String {
        if let existing = mapping[id] {
            return existing
        }
        let newId = "call_\(counter)"
        mapping[id] = newId
        counter += 1
        return newId
    }

    return steps.map { step in
        ComparableStep(
            stepType: step.stepType,
            toolCallIds: step.toolCallIds.map(mapId),
            toolResults: step.toolResults.map { content in
                switch content {
                case .toolResult(let toolName, let callId, let canonicalResult):
                    return .toolResult(toolName: toolName, callId: mapId(callId), canonicalResult: canonicalResult)
                case .toolCall(let toolName, let callId, let canonicalArguments):
                    return .toolCall(toolName: toolName, callId: mapId(callId), canonicalArguments: canonicalArguments)
                case .text:
                    return content
                }
            },
            text: step.text
        )
    }
}

extension ToolResult {
    func toComparableContent(toolName: String?) throws -> ComparableContent {
        switch result {
        case .text(let text):
            return .toolResult(toolName: toolName, callId: toolCallId, canonicalResult: text)
        case .json(let data):
            let object = try JSONSerialization.jsonObject(with: data)
            let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let string = String(data: canonical, encoding: .utf8) else {
                throw ScenarioError.invalidJSONResult
            }
            return .toolResult(toolName: toolName, callId: toolCallId, canonicalResult: string)
        case .error(let message):
            return .toolResult(toolName: toolName, callId: toolCallId, canonicalResult: message)
        case .data(let data, _):
            let base64 = data.base64EncodedString()
            return .toolResult(toolName: toolName, callId: toolCallId, canonicalResult: base64)
        case .image, .file:
            throw ScenarioError.unsupportedVercelContent("Binary tool results not supported in parity tests")
        }
    }
}

// MARK: - Summaries

struct ToolCallSummary: Equatable {
    let toolName: String
    let canonicalArguments: String
}

struct ToolResultSummary: Equatable {
    let toolName: String?
    let canonicalResult: String
}

func toolCallSummaries(from messages: [ComparableMessage]) -> [ToolCallSummary] {
    var summaries: [ToolCallSummary] = []
    for message in messages {
        for content in message.contents {
            if case .toolCall(let toolName, _, let canonicalArguments) = content {
                summaries.append(ToolCallSummary(toolName: toolName, canonicalArguments: canonicalArguments))
            }
        }
    }
    return summaries
}

func toolResultSummaries(from messages: [ComparableMessage]) -> [ToolResultSummary] {
    var summaries: [ToolResultSummary] = []
    for message in messages {
        for content in message.contents {
            if case .toolResult(let toolName, _, let canonicalResult) = content {
                summaries.append(ToolResultSummary(toolName: toolName, canonicalResult: canonicalResult))
            }
        }
    }
    return summaries
}

func finalAssistantTexts(from messages: [ComparableMessage]) -> [String] {
    messages
        .filter { $0.role == "assistant" }
        .compactMap { message in
            message.contents.compactMap { content -> String? in
                if case .text(let text) = content { return text }
                return nil
            }.last
        }
}
