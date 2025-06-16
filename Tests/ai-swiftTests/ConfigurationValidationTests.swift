import Testing
import Foundation
@testable import ai_swift

@Test func testConfigurationValidation() async throws {
    // Test configuration validation in mock provider with strict validation
    let strictConfig = MockConfiguration(strictValidation: true)
    let provider = MockProvider(apiKey: "test-key", configuration: strictConfig)
    
    // Test valid configuration
    let validConfig = ModelConfiguration.default
        .temperature(1.0)
        .maxTokens(2000)
    
    try provider.validateConfiguration(validConfig)
    
    // Test invalid temperature (should throw with strict validation)
    let invalidTempConfig = ModelConfiguration.default.temperature(3.0)
    
    do {
        try provider.validateConfiguration(invalidTempConfig)
        #expect(Bool(false), "Should have thrown validation error for high temperature")
    } catch {
        #expect(error is AIProviderError)
    }
    
    // Test invalid max tokens
    let invalidTokensConfig = ModelConfiguration.default.maxTokens(5000)
    
    do {
        try provider.validateConfiguration(invalidTokensConfig)
        #expect(Bool(false), "Should have thrown validation error for high maxTokens")
    } catch {
        #expect(error is AIProviderError)
    }
}