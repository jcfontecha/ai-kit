import Testing
import Foundation
@testable import AIKit

// This file serves as the main test entry point for the ai-swift package.
// 
// Individual test suites have been organized into separate files for better maintainability:
// - BasicArchitectureTests.swift: Core architecture and setup tests
// - TextGenerationTests.swift: Text generation functionality tests  
// - StreamingTests.swift: Streaming functionality tests
// - ObjectGenerationTests.swift: Object generation and schema tests
// - ToolExecutionTests.swift: Tool calling and execution tests
// - MiddlewareTests.swift: Middleware chain and transformation tests
// - ConfigurationValidationTests.swift: Configuration validation tests
//
// Add any miscellaneous tests that don't fit into the above categories here.

@Test func testPackageImport() {
    // Basic smoke test to ensure the package imports correctly
    _ = AIKit.client()
    #expect(Bool(true)) // Client creation succeeded
    
    let provider = AIKit.mockProvider()
    #expect(provider.name == "Mock Provider", "Should create mock provider")
}