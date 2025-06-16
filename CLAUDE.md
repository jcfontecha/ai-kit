# CLAUDE.md

Swift AI SDK - A type-safe, protocol-oriented Swift framework for AI model interactions, inspired by the Vercel AI SDK.

## ⚠️ CRITICAL: Vercel AI SDK Reference Requirement

**IMPERATIVE**: Before implementing ANY feature, you MUST research how Vercel AI SDK implements it:

1. **Online Documentation**: Visit https://ai-sdk.dev/docs for public API patterns
2. **Local Implementation**: Study `vercel-sdk/content/docs/` and `vercel-sdk/examples/` for technical details
3. **Plan Swift Translation**: Adapt TypeScript patterns to Swift idioms while maintaining API compatibility

Never implement features based on assumptions. Always consult Vercel AI SDK first.

## Development Commands

### 🚨 Build Early and Often
Swift compiler errors cascade quickly. Build after every small change:

```bash
swift build              # Build constantly after code changes
swift test               # Run all tests
swift test --filter testName  # Run specific test
```

**Rule**: Never write more than 5-10 lines without building.

## Core Architecture

Three-layer design: `AIClient` (Framework) → `LanguageModel` (Configuration) → `AIProvider` (Translation)

- **AIClient**: Actor-based orchestration with async/await and streaming
- **LanguageModel**: Configuration container with builder pattern
- **AIProvider**: Protocol for provider-specific API translation

**Key Types** (`Sources/ai-swift/Types/`):
- Messages, Streaming, Responses, Tools, Errors, Usage, ObjectSchema

## Development Patterns

### Provider Implementation
```swift
public struct YourProvider: AIProvider {
    public let name = "YourProvider"
    public func languageModel(_ modelId: String) -> LanguageModel
    public func generateTextRaw(_ request: ProviderRequest) async throws -> ProviderResponse
    public func streamTextRaw(_ request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}
```

### Testing Strategy
- Use `MockProvider` for all test scenarios
- Tests organized by feature complexity
- Current: OpenAI provider implemented with comprehensive test coverage
- See `TEST-PLAN.md` for implementation roadmap

## Key Files
- `Sources/ai-swift/ai_swift.swift`: Main module interface
- `Sources/ai-swift/Core/`: Core architecture components
- `Tests/ai-swiftTests/`: Test suite with mock implementations

## Provider Implementation Workflow

1. **Research**: Study Vercel AI SDK provider patterns and official API docs
2. **Plan**: Create todo list, set up file structure in `Sources/ai-swift/Providers/`
3. **Implement**: Build provider struct, API types, generateTextRaw, streamTextRaw, error handling
4. **Verify**: Build check, platform requirements, type safety, integration testing

## Test-Driven Development (TDD) Workflow

**5-Step TDD Methodology**:

1. **Study Architecture**: Read `SWIFT_AI_SDK_CORE_ARCHITECTURE.md` for Swift patterns
2. **Write Failing Tests (RED)**: Create tests based on Vercel AI SDK patterns
3. **Research Vercel Implementation**: Study `vercel-sdk/content/docs/` and examples
4. **Implement Swift Solution (GREEN)**: Write minimal code using Swift idioms
5. **Verify and Refactor**: Run all tests, clean up code, update documentation

**TDD Cycle Commands**:
```bash
swift test --filter testName  # Run single test (RED/GREEN)
swift test                    # Run all tests (verify)
swift build                   # Ensure compilation
```

## ⚠️ CRITICAL: E2E Test Model Requirements

**MANDATORY**: For E2E tests in `Tests/ai-swiftTests/E2EOpenAITests.swift`:

- **ALWAYS use `gpt-4.1-nano`** - This is the ONLY model allowed for E2E testing
- **NEVER change the model** - It's specifically chosen for cost-effectiveness and consistency
- **All E2E tests must use this exact model name**: `"gpt-4.1-nano"`

This ensures predictable costs and consistent test behavior across all E2E test scenarios.

This methodology ensures high-quality, maintainable code that mirrors Vercel AI SDK while being idiomatic to Swift.