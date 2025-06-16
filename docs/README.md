# AIKit Documentation

Welcome to the comprehensive documentation for AIKit, a Swift framework for AI model interactions inspired by the Vercel AI SDK.

## 📚 Documentation Structure

### Getting Started
- [Installation](getting-started/installation.md) - How to add AIKit to your project
- [Quick Start](getting-started/quick-start.md) - Your first AIKit application
- [Configuration](getting-started/configuration.md) - Model and client configuration

### Guides
- [Text Generation](guides/text-generation.md) - Generate text with AI models
- [Streaming](guides/streaming.md) - Real-time text streaming
- [Object Generation](guides/object-generation.md) - Generate structured objects
- [Tool Calling](guides/tool-calling.md) - Function calling and tool integration
- [Middleware](guides/middleware.md) - Request/response transformation
- [Error Handling](guides/error-handling.md) - Managing errors and exceptions

### API Reference
- [AIClient](api-reference/ai-client.md) - Main framework interface
- [LanguageModel](api-reference/language-model.md) - Model configuration
- [AIProvider](api-reference/ai-provider.md) - Provider protocol
- [Types](api-reference/types.md) - Core data types
- [Middleware](api-reference/middleware.md) - Middleware system

### Examples
- [Basic Usage](examples/basic-usage.md) - Simple examples
- [Advanced Patterns](examples/advanced-patterns.md) - Complex use cases
- [Provider Examples](examples/provider-examples.md) - Working with different providers
- [Real-world Applications](examples/real-world.md) - Production examples

## 🚀 Quick Navigation

### I want to...
- **Get started quickly** → [Quick Start Guide](getting-started/quick-start.md)
- **Generate text** → [Text Generation Guide](guides/text-generation.md)
- **Stream responses** → [Streaming Guide](guides/streaming.md)
- **Generate objects** → [Object Generation Guide](guides/object-generation.md)
- **Use tools/functions** → [Tool Calling Guide](guides/tool-calling.md)
- **Create a provider** → [Provider Implementation Guide](guides/provider-implementation.md)
- **Handle errors** → [Error Handling Guide](guides/error-handling.md)
- **See examples** → [Examples Directory](examples/)

## 📖 Key Concepts

AIKit follows a three-layer architecture:

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────┐
│   AIClient  │───▶│ LanguageModel│───▶│   AIProvider    │
│ (Framework) │    │ (Configuration)│    │ (Translation)   │
└─────────────┘    └──────────────┘    └─────────────────┘
```

- **AIClient**: Framework implementation that handles orchestration, middleware, tool execution, and streaming
- **LanguageModel**: Configuration container with provider, model ID, and parameters  
- **AIProvider**: Translation layer between SDK standard format and provider APIs

## 🔧 Core Features

- **Type-Safe API**: Comprehensive Swift types with full Codable support
- **Streaming Support**: Real-time text and object generation with AsyncSequence
- **Tool Integration**: Function calling with automatic execution
- **Structured Output**: JSON schema-validated object generation  
- **Provider Agnostic**: Clean abstraction over multiple AI providers
- **Middleware System**: Extensible request/response transformation
- **Swift-Native**: Actor-based concurrency, builder patterns, and strong typing

## 🤝 Contributing

Found an issue with the documentation? Please [open an issue](https://github.com/jcfontecha/ai-kit/issues) or submit a pull request.

## 📄 License

AIKit is released under the MIT License. See [LICENSE](../LICENSE) for details.