# LanguageModel API Reference

`LanguageModel` is a configuration container that holds model parameters and provider information. It uses the builder pattern for easy configuration.

## Overview

```swift
public struct LanguageModel {
    public let provider: AIProvider
    public let modelId: String
    public let configuration: ModelConfiguration
}
```

## Creating a LanguageModel

### From Provider

```swift
let provider = OpenAIProvider(apiKey: "your-key")
let model = provider.languageModel("gpt-4")
```

### Direct Creation

```swift
let model = LanguageModel(
    provider: provider,
    modelId: "gpt-4",
    configuration: ModelConfiguration()
)
```

## Configuration Methods

All configuration methods return a new `LanguageModel` instance (immutable).

### temperature(_:)

Sets the randomness/creativity of responses.

```swift
func temperature(_ value: Double) -> LanguageModel
```

**Parameters:**
- `value`: Temperature value (0.0 - 2.0)
  - `0.0`: Deterministic, always picks most likely token
  - `0.7`: Balanced (default)
  - `1.0+`: More random and creative

**Example:**
```swift
// Conservative/deterministic
let preciseModel = model.temperature(0.1)

// Balanced
let balancedModel = model.temperature(0.7)

// Creative
let creativeModel = model.temperature(0.9)
```

### maxTokens(_:)

Sets the maximum number of tokens to generate.

```swift
func maxTokens(_ value: Int) -> LanguageModel
```

**Parameters:**
- `value`: Maximum tokens (1 - provider limit)

**Example:**
```swift
let shortModel = model.maxTokens(100)      // Brief responses
let mediumModel = model.maxTokens(500)     // Moderate length
let longModel = model.maxTokens(2000)      // Long responses
```

### topP(_:)

Sets nucleus sampling parameter.

```swift
func topP(_ value: Double) -> LanguageModel
```

**Parameters:**
- `value`: Top-p value (0.0 - 1.0)
  - Lower values = more focused
  - Higher values = more diverse

**Example:**
```swift
let focusedModel = model.topP(0.5)    // Only top 50% probable tokens
let diverseModel = model.topP(0.95)   // Consider 95% of probability mass
```

### frequencyPenalty(_:)

Reduces repetition of tokens based on frequency.

```swift
func frequencyPenalty(_ value: Double) -> LanguageModel
```

**Parameters:**
- `value`: Penalty value (-2.0 - 2.0)
  - Positive values reduce repetition
  - Negative values encourage repetition

**Example:**
```swift
let antiRepetitiveModel = model.frequencyPenalty(0.8)  // Reduce repetition
let allowRepetitionModel = model.frequencyPenalty(0.0) // Default behavior
```

### presencePenalty(_:)

Encourages discussing new topics.

```swift
func presencePenalty(_ value: Double) -> LanguageModel
```

**Parameters:**
- `value`: Penalty value (-2.0 - 2.0)
  - Positive values encourage new topics
  - Negative values encourage staying on topic

**Example:**
```swift
let exploratoryModel = model.presencePenalty(0.6)  // Encourage new topics
let focusedModel = model.presencePenalty(-0.3)     // Stay on topic
```

### stopSequences(_:)

Sets tokens that stop generation.

```swift
func stopSequences(_ sequences: [String]) -> LanguageModel
```

**Parameters:**
- `sequences`: Array of stop sequences

**Example:**
```swift
let model = model.stopSequences(["END", "STOP", "\\n\\n"])
```

### seed(_:)

Sets a seed for reproducible outputs.

```swift
func seed(_ value: Int) -> LanguageModel
```

**Parameters:**
- `value`: Seed value for reproducibility

**Example:**
```swift
let reproducibleModel = model.seed(42)
```

### tools(_:)

Adds tools/functions to the model.

```swift
func tools(_ tools: [Tool]) -> LanguageModel
```

**Parameters:**
- `tools`: Array of available tools

**Example:**
```swift
let weatherTool = Tool.function(
    name: "get_weather",
    description: "Get current weather",
    parameters: .object(properties: [
        "location": .string(description: "City name")
    ])
)

let modelWithTools = model.tools([weatherTool])
```

### providerSpecific(_:)

Sets provider-specific parameters.

```swift
func providerSpecific(_ parameters: [String: Any]) -> LanguageModel
```

**Parameters:**
- `parameters`: Dictionary of provider-specific settings

**Example:**
```swift
// OpenAI-specific parameters
let openAIModel = model.providerSpecific([
    "logit_bias": "{\\"50256\\": -100}",  // Reduce likelihood of specific tokens
    "user": "user-123"                    // User identifier
])

// Anthropic-specific parameters
let anthropicModel = model.providerSpecific([
    "top_k": 40,                          // Top-k sampling
    "metadata": ["user_id": "123"]        // Request metadata
])
```

## Configuration Builders

### configure(_:)

Applies a configuration block.

```swift
func configure(_ configBlock: (inout ModelConfiguration) -> Void) -> LanguageModel
```

**Example:**
```swift
let model = provider.languageModel("gpt-4")
    .configure { config in
        config.temperature = 0.8
        config.maxTokens = 500
        config.topP = 0.9
    }
```

### configure(with:)

Applies a predefined configuration.

```swift
func configure(with configuration: ModelConfiguration) -> LanguageModel
```

**Example:**
```swift
let creativeConfig = ModelConfiguration(
    temperature: 0.9,
    topP: 0.95,
    frequencyPenalty: 0.7
)

let model = provider.languageModel("gpt-4")
    .configure(with: creativeConfig)
```

## Predefined Configurations

AIKit provides common configurations:

### Creative Configuration

```swift
let creativeModel = provider.languageModel("gpt-4")
    .configure(with: AIKit.creativeConfiguration)

// Equivalent to:
// .temperature(0.9)
// .topP(0.95)
// .frequencyPenalty(0.7)
```

### Precise Configuration

```swift
let preciseModel = provider.languageModel("gpt-4")
    .configure(with: AIKit.preciseConfiguration)

// Equivalent to:
// .temperature(0.1)
// .topP(0.5)
// .frequencyPenalty(0.0)
```

### Balanced Configuration

```swift
let balancedModel = provider.languageModel("gpt-4")
    .configure(with: AIKit.balancedConfiguration)

// Equivalent to:
// .temperature(0.7)
// .topP(0.9)
// .frequencyPenalty(0.3)
```

## Method Chaining

All configuration methods can be chained:

```swift
let model = provider.languageModel("gpt-4")
    .temperature(0.8)
    .maxTokens(1000)
    .topP(0.9)
    .frequencyPenalty(0.5)
    .stopSequences(["END"])
    .seed(42)
```

## Model Information

### Properties

```swift
public struct LanguageModel {
    public let provider: AIProvider          // Associated provider
    public let modelId: String              // Model identifier
    public let configuration: ModelConfiguration  // Current configuration
    
    // Computed properties
    public var temperature: Double { configuration.temperature }
    public var maxTokens: Int? { configuration.maxTokens }
    public var topP: Double { configuration.topP }
    public var frequencyPenalty: Double { configuration.frequencyPenalty }
    public var presencePenalty: Double { configuration.presencePenalty }
    public var stopSequences: [String] { configuration.stopSequences }
    public var seed: Int? { configuration.seed }
    public var tools: [Tool] { configuration.tools }
}
```

### Capabilities

Check what the model supports:

```swift
// Check if model supports streaming
if model.provider.capabilities.streaming {
    let stream = client.streamText(model, prompt: "Hello")
}

// Check if model supports tool calling
if model.provider.capabilities.toolCalling {
    let modelWithTools = model.tools([weatherTool])
}

// Check if model supports object generation
if model.provider.capabilities.objectGeneration {
    let response = try await client.generateObject(model, prompt: "...", schema: schema)
}
```

## Model Validation

Validate configuration before use:

```swift
extension LanguageModel {
    func validate() throws {
        guard configuration.temperature >= 0 && configuration.temperature <= 2 else {
            throw AIError.invalidConfiguration("Temperature must be between 0 and 2")
        }
        
        if let maxTokens = configuration.maxTokens {
            guard maxTokens > 0 else {
                throw AIError.invalidConfiguration("Max tokens must be positive")
            }
        }
        
        guard configuration.topP >= 0 && configuration.topP <= 1 else {
            throw AIError.invalidConfiguration("Top-p must be between 0 and 1")
        }
    }
}

// Usage
do {
    try model.validate()
    let response = try await client.generateText(model, prompt: "Hello")
} catch {
    print("Invalid model configuration: \\(error)")
}
```

## Best Practices

### 1. Use Appropriate Settings for Task

```swift
// For factual Q&A
let factualModel = provider.languageModel("gpt-4")
    .temperature(0.1)
    .maxTokens(300)

// For creative writing
let creativeModel = provider.languageModel("gpt-4")
    .temperature(0.9)
    .topP(0.95)
    .maxTokens(1500)

// For code generation
let codeModel = provider.languageModel("gpt-4")
    .temperature(0.2)
    .maxTokens(800)
    .stopSequences(["```"])
```

### 2. Configure for Cost Efficiency

```swift
// For development/testing
let devModel = provider.languageModel("gpt-3.5-turbo")
    .maxTokens(200)
    .temperature(0.7)

// For production
let prodModel = provider.languageModel("gpt-4")
    .maxTokens(1000)
    .temperature(0.7)
```

### 3. Use Seeds for Testing

```swift
// Reproducible outputs for testing
let testModel = provider.languageModel("gpt-4")
    .seed(42)
    .temperature(0.0)  // Most deterministic
```

### 4. Configure Based on Content Type

```swift
enum ContentType {
    case technical, creative, conversational
}

func createModel(for contentType: ContentType) -> LanguageModel {
    let baseModel = provider.languageModel("gpt-4")
    
    switch contentType {
    case .technical:
        return baseModel
            .temperature(0.3)
            .maxTokens(800)
            .frequencyPenalty(0.2)
            
    case .creative:
        return baseModel
            .temperature(0.9)
            .topP(0.95)
            .maxTokens(1500)
            .frequencyPenalty(0.7)
            
    case .conversational:
        return baseModel
            .temperature(0.7)
            .maxTokens(500)
            .frequencyPenalty(0.3)
    }
}
```

## Model Comparison

Compare different configurations:

```swift
struct ModelBenchmark {
    let name: String
    let model: LanguageModel
    let averageTokens: Int
    let averageLatency: Double
    let quality: Double
}

func benchmarkModels(prompt: String) async throws -> [ModelBenchmark] {
    let models = [
        ("Conservative", provider.languageModel("gpt-4").temperature(0.1)),
        ("Balanced", provider.languageModel("gpt-4").temperature(0.7)),
        ("Creative", provider.languageModel("gpt-4").temperature(0.9))
    ]
    
    var benchmarks: [ModelBenchmark] = []
    
    for (name, model) in models {
        let startTime = Date()
        let response = try await client.generateText(model, prompt: prompt)
        let latency = Date().timeIntervalSince(startTime)
        
        let benchmark = ModelBenchmark(
            name: name,
            model: model,
            averageTokens: response.usage.completionTokens,
            averageLatency: latency,
            quality: evaluateQuality(response.text)
        )
        
        benchmarks.append(benchmark)
    }
    
    return benchmarks
}
```

## See Also

- [AIProvider](ai-provider.md) - Provider implementation
- [ModelConfiguration](model-configuration.md) - Configuration structure
- [AIClient](ai-client.md) - Client interface
- [Tools](tools.md) - Tool integration