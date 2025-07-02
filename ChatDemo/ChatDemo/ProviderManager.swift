//
//  ProviderManager.swift
//  ChatDemo
//
//  Created by Juan Carlos on 7/1/25.
//

import Foundation
import AIKit

@available(iOS 16.0, macOS 13.0, *)
struct ProviderManager {
    static var shared = ProviderManager()
    
    let provider: any AIProvider
    let isUsingRealAPI: Bool
    
    init() {
        if let apiKey = ConfigLoader.loadAPIKey(), !apiKey.isEmpty {
            // Use real OpenAI provider
            provider = OpenAIProvider(apiKey: apiKey)
            isUsingRealAPI = true
            print("✅ Using OpenAI provider with API key")
        } else {
            // Fall back to mock provider
            provider = MockProvider()
            isUsingRealAPI = false
            print("ℹ️ Using mock provider (no API key found)")
        }
    }
    
    func languageModel(_ modelId: String) -> LanguageModel {
        // For OpenAI, use real models; for mock, use the mock models
        if isUsingRealAPI {
            // Map demo model names to real OpenAI models
            switch modelId {
            case "gpt-4o-mini", "gpt-4.1-nano":
                return provider.languageModel("gpt-4o-mini")
            case "gpt-4o":
                return provider.languageModel("gpt-4o")
            default:
                return provider.languageModel(modelId)
            }
        } else {
            return provider.languageModel(modelId)
        }
    }
}