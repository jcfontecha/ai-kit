import Foundation
@testable import AIKit

final class VercelFixtureProvider: AIProvider, @unchecked Sendable {
    let name = "VercelFixtureProvider"
    let supportedGenerationModes: Set<GenerationMode> = [.auto, .tool, .json]
    let defaultGenerationMode: GenerationMode = .auto

    private let responses: [ProviderResponse]
    private var index: Int = 0

    init(responses: [ProviderResponse]) {
        self.responses = responses
    }

    func languageModel(_ modelId: String) -> LanguageModel {
        LanguageModel(provider: self, modelId: modelId)
    }

    func validateConfiguration(_ configuration: ModelConfiguration) throws {}

    func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse {
        guard index < responses.count else {
            throw ScenarioError.missingExpectedResult
        }
        defer { index += 1 }
        return responses[index]
    }

    func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    var didConsumeAllResponses: Bool {
        index == responses.count
    }
}
