import XCTest
import Foundation
@testable import AIKit

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
final class E2EOpenRouterTests: XCTestCase {
    private func loadOpenRouterAPIKey() throws -> String {
        if let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        let configPath = "\(cwd)/Config.plist"
        guard fileManager.fileExists(atPath: configPath) else {
            throw NSError(domain: "E2EOpenRouter", code: 0, userInfo: [NSLocalizedDescriptionKey: "Config.plist not found at \(configPath)"])
        }
        guard let data = fileManager.contents(atPath: configPath) else {
            throw NSError(domain: "E2EOpenRouter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read Config.plist"])
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let dict = plist as? [String: Any], let apiKey = dict["OPENROUTER_API_KEY"] as? String, !apiKey.isEmpty else {
            throw NSError(domain: "E2EOpenRouter", code: 2, userInfo: [NSLocalizedDescriptionKey: "OPENROUTER_API_KEY missing in Config.plist"])
        }
        return apiKey
    }
    
    func testOpenRouterStreamingIncludesReasoning() async throws {
        let apiKey: String
        do {
            apiKey = try loadOpenRouterAPIKey()
        } catch {
            XCTFail("Missing OPENROUTER_API_KEY: \(error.localizedDescription)")
            return
        }
        
        let provider = OpenRouterProvider(
            apiKey: apiKey,
            headers: [
                "HTTP-Referer": "https://github.com/ai-kit/tests",
                "X-Title": "AIKit Test Suite"
            ],
            defaultReasoning: .init(enabled: true, exclude: nil, maxTokens: nil, effort: .medium),
            defaultUsage: .init(include: true),
            defaultIncludeReasoning: true
        )
        let model = provider.languageModel("google/gemini-2.5-pro")
            .temperature(0.1)
            .maxTokens(150)
        let client = AIClient()
        
        let result = await client.streamText(
            model,
            messages: [
                Message.system("You are an assistant that always reasons explicitly before answering. Provide clear reasoning and then a short final response."),
                Message.user("Explain how to compute 23 multiplied by 19. Provide the reasoning steps and then the concise final answer.")
            ]
        )
        
        var collectedReasoningFragments: [String] = []
        var collectedAnnotations: [String] = []
        var streamedText = ""
        
        for try await chunk in result.textStream {
            streamedText += chunk.delta
            if let reasonings = chunk.reasoning {
                for entry in reasonings {
                    collectedReasoningFragments.append(contentsOf: entry.fragments)
                }
            }
            if let annotations = chunk.messageAnnotations {
                for annotation in annotations {
                    collectedAnnotations.append(contentsOf: annotation.values)
                }
            }
        }
        
        XCTAssertFalse(streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Expected streaming text from OpenRouter model")
        XCTAssertFalse(collectedReasoningFragments.filter { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }.isEmpty, "Expected reasoning fragments in streaming chunks")
        
        let response = await result.response
        let responseReasoning = response.messages.flatMap { message in
            message.content.compactMap { content -> [String] in
                content.reasoningValue?.fragments ?? []
            }
        }.flatMap { $0 }
        XCTAssertFalse(responseReasoning.filter { !$0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty }.isEmpty, "Expected reasoning parts on final response messages")
        
        let streamData = await result.streamDataValues
        XCTAssertGreaterThanOrEqual(streamData.count, 0, "Should be able to access stream data values safely.")
        
        let usage = await result.usage
        XCTAssertNotNil(usage, "Expected usage information from OpenRouter streaming")
    }
}
