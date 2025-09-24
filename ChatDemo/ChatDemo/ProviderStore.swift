//
//  ProviderStore.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import Foundation
import Combine
import AIKit

@available(iOS 16.0, macOS 13.0, *)
@MainActor
final class ProviderStore: ObservableObject {
    enum ProviderKind: String, CaseIterable, Identifiable {
        case openAI = "OpenAI"
        case anthropic = "Anthropic"
        case openRouter = "OpenRouter"
        case mock = "Mock"
        
        var id: String { rawValue }
        var displayName: String { rawValue }
    }
    
    struct ProviderEntry {
        let provider: any AIProvider
        let defaultModel: String
        let suggestedModels: [String]
        let unavailableReason: String?
        
        var isAvailable: Bool { unavailableReason == nil }
    }
    
    struct Selection: Equatable {
        var provider: ProviderKind
        var modelId: String
    }
    
    @Published private(set) var entries: [ProviderKind: ProviderEntry]
    @Published private(set) var selection: Selection {
        didSet {
            modelOverrides[selection.provider] = selection.modelId
        }
    }
    
    private var modelOverrides: [ProviderKind: String]
    
    init() {
        var providerEntries: [ProviderKind: ProviderEntry] = [:]
        var preferredProvider: ProviderKind = .mock
        var preferredModel: String = "gpt-4o-mini"
        let mockProvider = MockProvider()
        
        providerEntries[.mock] = ProviderEntry(
            provider: mockProvider,
            defaultModel: "gpt-4o-mini",
            suggestedModels: [
                "gpt-4o-mini",
                "gpt-4o",
                "claude-3.5-sonnet"
            ],
            unavailableReason: nil
        )
        
        if let openAIKey = ConfigLoader.loadAPIKey(), openAIKey.isEmpty == false {
            let provider = OpenAIProvider(apiKey: openAIKey)
            providerEntries[.openAI] = ProviderEntry(
                provider: provider,
                defaultModel: "gpt-4o-mini",
                suggestedModels: [
                    "gpt-4o-mini",
                    "gpt-4o",
                    "o4-mini"
                ],
                unavailableReason: nil
            )
            preferredProvider = .openAI
            preferredModel = providerEntries[.openAI]?.defaultModel ?? preferredModel
        } else {
            providerEntries[.openAI] = ProviderEntry(
                provider: mockProvider,
                defaultModel: "gpt-4o-mini",
                suggestedModels: [
                    "gpt-4o-mini",
                    "gpt-4o"
                ],
                unavailableReason: "Missing OPENAI_API_KEY"
            )
        }
        
        if let anthropicKey = ConfigLoader.loadAnthropicAPIKey(), anthropicKey.isEmpty == false {
            let provider = AnthropicProvider(apiKey: anthropicKey)
            providerEntries[.anthropic] = ProviderEntry(
                provider: provider,
                defaultModel: "claude-3.5-sonnet",
                suggestedModels: [
                    "claude-3.5-sonnet",
                    "claude-3.5-haiku",
                    "claude-3-haiku"
                ],
                unavailableReason: nil
            )
            if preferredProvider == .mock {
                preferredProvider = .anthropic
                preferredModel = providerEntries[.anthropic]?.defaultModel ?? preferredModel
            }
        } else {
            providerEntries[.anthropic] = ProviderEntry(
                provider: mockProvider,
                defaultModel: "claude-3.5-sonnet",
                suggestedModels: [
                    "claude-3.5-sonnet",
                    "claude-3-haiku"
                ],
                unavailableReason: "Missing ANTHROPIC_API_KEY"
            )
        }
        
        if let openRouterKey = ConfigLoader.loadOpenRouterAPIKey(), openRouterKey.isEmpty == false {
            let provider = OpenRouterProvider(
                apiKey: openRouterKey,
                compatibility: .strict,
                headers: ["HTTP-Referer": "AIKit Demo"],
                debugLogging: true
            )
            providerEntries[.openRouter] = ProviderEntry(
                provider: provider,
                defaultModel: "anthropic/claude-3.5-sonnet",
                suggestedModels: [
                    "anthropic/claude-3.5-sonnet",
                    "openai/gpt-4o-mini",
                    "google/gemini-1.5-flash"
                ],
                unavailableReason: nil
            )
            if preferredProvider == .mock {
                preferredProvider = .openRouter
                preferredModel = providerEntries[.openRouter]?.defaultModel ?? preferredModel
            }
        } else {
            providerEntries[.openRouter] = ProviderEntry(
                provider: mockProvider,
                defaultModel: "anthropic/claude-3.5-sonnet",
                suggestedModels: [
                    "anthropic/claude-3.5-sonnet",
                    "openai/gpt-4o-mini"
                ],
                unavailableReason: "Missing OPENROUTER_API_KEY"
            )
        }
        
        entries = providerEntries
        modelOverrides = [:]
        selection = Selection(provider: preferredProvider, modelId: preferredModel)
    }
    
    var isUsingRealAPI: Bool {
        guard let entry = entries[selection.provider] else {
            return false
        }
        return selection.provider != .mock && entry.isAvailable
    }
    
    func selectProvider(_ provider: ProviderKind) {
        let model = modelOverrides[provider] ?? entries[provider]?.defaultModel ?? entries[.mock]?.defaultModel ?? "gpt-4o-mini"
        selection = Selection(provider: provider, modelId: model)
    }
    
    func setModel(_ modelId: String) {
        selection = Selection(provider: selection.provider, modelId: modelId)
    }
    
    func languageModel(_ fallbackModelId: String) -> LanguageModel {
        let resolvedModelId = resolvedModelId(fallbackModelId)
        if isUsingRealAPI, let entry = entries[selection.provider] {
            return entry.provider.languageModel(resolvedModelId)
        }
        let mockProvider = entries[.mock]!.provider
        return mockProvider.languageModel(fallbackModelId)
    }
    
    func resolvedModelId(_ fallbackModelId: String) -> String {
        guard isUsingRealAPI else { return fallbackModelId }
        if let override = modelOverrides[selection.provider], override.isEmpty == false {
            return override
        }
        return selection.modelId.isEmpty ? fallbackModelId : selection.modelId
    }
    
    func selectionSummary(fallbackModelId: String) -> String {
        if isUsingRealAPI {
            let providerName = selection.provider.displayName
            let modelName = resolvedModelId(fallbackModelId)
            return "\(providerName) • \(modelName)"
        }
        return "Mock Provider"
    }
    
    func availabilityMessage(for provider: ProviderKind) -> String? {
        entries[provider]?.unavailableReason
    }
    
    func suggestedModels(for provider: ProviderKind) -> [String] {
        entries[provider]?.suggestedModels ?? []
    }
    
    func selectionIdentity(context: String, fallbackModelId: String) -> String {
        let activeModel = isUsingRealAPI ? resolvedModelId(fallbackModelId) : fallbackModelId
        return "\(selection.provider.id)|\(activeModel)|\(context)"
    }
}
