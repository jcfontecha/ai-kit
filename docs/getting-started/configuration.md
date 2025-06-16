# Configuration

This guide covers how to configure AIKit models and clients for optimal performance.

## Model Configuration

### Basic Configuration

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.7)
    .maxTokens(500)
    .topP(0.9)
```

### All Configuration Options

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.8)           // Randomness (0.0-1.0)
    .maxTokens(1000)           // Maximum tokens to generate
    .topP(0.9)                 // Nucleus sampling
    .frequencyPenalty(0.5)     // Reduce repetition
    .presencePenalty(0.3)      // Encourage new topics
    .stopSequences(["END", "STOP"])  // Stop generation tokens
    .seed(42)                  // Reproducible outputs
```

## Parameter Explanations

### Temperature
Controls randomness in generation:
- `0.0`: Deterministic, always picks most likely token
- `0.3-0.7`: Good balance for most tasks
- `0.8-1.0`: More creative and varied outputs
- `1.0+`: Highly random (may produce nonsense)

```swift
// For factual, precise responses
let preciseModel = provider.languageModel("gpt-4").temperature(0.1)

// For creative writing
let creativeModel = provider.languageModel("gpt-4").temperature(0.9)
```

### Max Tokens
Maximum number of tokens to generate:

```swift
// Short responses
let shortModel = provider.languageModel("gpt-4").maxTokens(100)

// Long-form content
let longModel = provider.languageModel("gpt-4").maxTokens(2000)

// No limit (use provider's maximum)
let unlimitedModel = provider.languageModel("gpt-4") // Uses provider default
```

### Top-P (Nucleus Sampling)
Controls diversity by only considering tokens with cumulative probability <= p:

```swift
// More focused (only top tokens)
let focusedModel = provider.languageModel("gpt-4").topP(0.5)

// Balanced
let balancedModel = provider.languageModel("gpt-4").topP(0.9)

// More diverse
let diverseModel = provider.languageModel("gpt-4").topP(0.95)
```

### Frequency Penalty
Reduces likelihood of repeating tokens:

```swift
// Avoid repetition
let nonRepetitiveModel = provider.languageModel("gpt-4").frequencyPenalty(0.8)

// Allow some repetition
let allowRepetitionModel = provider.languageModel("gpt-4").frequencyPenalty(0.2)
```

### Stop Sequences
Tokens that stop generation:

```swift
let model = provider.languageModel("gpt-4")
    .stopSequences(["\\n\\n", "END", "---"])
```

## Predefined Configurations

AIKit provides common configurations:

### Creative Configuration
```swift
let creativeConfig = AIKit.creativeConfiguration
let model = provider.languageModel("gpt-4").configure(creativeConfig)

// Equivalent to:
// .temperature(0.9)
// .topP(0.95)
// .frequencyPenalty(0.7)
```

### Precise Configuration
```swift
let preciseConfig = AIKit.preciseConfiguration
let model = provider.languageModel("gpt-4").configure(preciseConfig)

// Equivalent to:
// .temperature(0.1)
// .topP(0.5)
// .frequencyPenalty(0.0)
```

### Balanced Configuration
```swift
let balancedConfig = AIKit.balancedConfiguration
let model = provider.languageModel("gpt-4").configure(balancedConfig)

// Equivalent to:
// .temperature(0.7)
// .topP(0.9)
// .frequencyPenalty(0.3)
```

## Provider-Specific Configuration

Some providers support additional parameters:

```swift
let model = provider.languageModel("gpt-4")
    .providerSpecific([
        "logit_bias": "{\\"50256\\": -100}",  // OpenAI logit bias
        "user": "user123",                    // OpenAI user identifier
        "tools": toolsArray                   // Provider-specific tools
    ])
```

## Client Configuration

### Basic Client
```swift
let client = AIKit.client()
```

### Client with Middleware
```swift
let client = AIKit.client(middleware: [
    AIKit.loggingMiddleware(),
    AIKit.rateLimitMiddleware(maxRequests: 100),
    AIKit.retryMiddleware(maxRetries: 3)
])
```

### Custom Client Configuration
```swift
let config = AIClientConfiguration(
    timeout: 30.0,           // Request timeout in seconds
    maxRetries: 3,           // Automatic retry attempts
    defaultMiddleware: true  // Include default middleware
)
let client = AIKit.client(configuration: config)
```

## Environment-Specific Configurations

### Development
```swift
#if DEBUG
let model = provider.languageModel("gpt-3.5-turbo")  // Cheaper for testing
    .temperature(0.5)
    .maxTokens(200)
#else
let model = provider.languageModel("gpt-4")          // Production model
    .temperature(0.7)
    .maxTokens(1000)
#endif
```

### Testing
```swift
func createTestModel() -> LanguageModel {
    let provider = MockProvider()
    return provider.languageModel("test-model")
        .temperature(0.0)  // Deterministic for tests
        .maxTokens(100)
}
```

## Configuration Patterns

### Builder Pattern
```swift
func createModel(for task: TaskType) -> LanguageModel {
    let baseModel = provider.languageModel("gpt-4")
    
    switch task {
    case .creative:
        return baseModel
            .temperature(0.9)
            .topP(0.95)
            .frequencyPenalty(0.7)
            
    case .analytical:
        return baseModel
            .temperature(0.3)
            .topP(0.7)
            .frequencyPenalty(0.2)
            
    case .factual:
        return baseModel
            .temperature(0.1)
            .topP(0.5)
            .frequencyPenalty(0.0)
    }
}
```

### Configuration Validation
```swift
func validateConfiguration(_ model: LanguageModel) throws {
    guard model.temperature >= 0 && model.temperature <= 2 else {
        throw ConfigurationError.invalidTemperature
    }
    
    guard model.maxTokens > 0 else {
        throw ConfigurationError.invalidMaxTokens
    }
}
```

## Best Practices

### 1. Start with Defaults
Begin with balanced settings and adjust based on results:

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.7)  // Good starting point
    .maxTokens(500)    // Reasonable limit
```

### 2. Use Environment Variables
Configure differently for different environments:

```swift
let temperature = Double(ProcessInfo.processInfo.environment["AI_TEMPERATURE"] ?? "0.7") ?? 0.7
let model = provider.languageModel("gpt-4").temperature(temperature)
```

### 3. Document Your Configurations
```swift
/// Creative writing configuration
/// - High temperature for creativity
/// - High top-p for diversity
/// - Frequency penalty to avoid repetition
let creativeModel = provider.languageModel("gpt-4")
    .temperature(0.9)
    .topP(0.95)
    .frequencyPenalty(0.7)
```

### 4. Test Different Configurations
```swift
let configurations = [
    ("conservative", 0.3, 0.7),
    ("balanced", 0.7, 0.9),
    ("creative", 0.9, 0.95)
]

for (name, temp, topP) in configurations {
    let model = provider.languageModel("gpt-4")
        .temperature(temp)
        .topP(topP)
    
    // Test and compare results
}
```

## Configuration Reference

| Parameter | Type | Range | Default | Description |
|-----------|------|-------|---------|-------------|
| temperature | Double | 0.0-2.0 | 0.7 | Controls randomness |
| maxTokens | Int | 1-∞ | Provider default | Maximum tokens to generate |
| topP | Double | 0.0-1.0 | 0.9 | Nucleus sampling threshold |
| frequencyPenalty | Double | -2.0-2.0 | 0.0 | Frequency penalty |
| presencePenalty | Double | -2.0-2.0 | 0.0 | Presence penalty |
| seed | Int | Any | nil | Reproducibility seed |
| stopSequences | [String] | Any | [] | Stop generation tokens |

## Next Steps

- [Text Generation](../guides/text-generation.md) - Generate text with your configured models
- [Streaming](../guides/streaming.md) - Stream responses in real-time
- [Error Handling](../guides/error-handling.md) - Handle configuration errors