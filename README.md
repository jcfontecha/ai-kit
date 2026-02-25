# AIKit

Swift-first, type-safe AI SDK for iOS and macOS apps.

AIKit translates the semantics of Vercel's AI SDK into Swift APIs that feel native to Apple platforms, with strong typing, structured concurrency, and comprehensive tests.

## Why AIKit

- Swift-first API design (`generateText`, `streamText`, `Agent`, `ChatStore`)
- Type-safe outputs and tool calling
- Multi-provider architecture with shared wire/protocol types
- Streaming support for text, reasoning, tool input deltas, tool calls/results, and step boundaries
- Large parity-oriented test suite

## Requirements

- iOS 26+
- macOS 26+
- Swift 6.2+

## Installation (SwiftPM)

Add the package dependency:

```swift
dependencies: [
  .package(url: "https://github.com/jcfontecha/ai-kit.git", from: "0.1.0"),
]
```

Then depend on one or more products:

- `AIKit`
- `AIKitProviders`
- `AIKitElements`
- `AIKitOpenRouter`
- `AIKitOpenClaw`
- `AIKitOpenAI`
- `AIKitReplicate`
- `AIKitFal`
- `AIKitMacro`

## Quickstart

```swift
import AIKit
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

let result = try await generateText(.init(
  model: model,
  prompt: "Write one sentence about Swift concurrency.",
  output: Output.text()
))

print(result.text)
```

Streaming:

```swift
let stream = streamText(.init(
  model: model,
  prompt: "Stream 3 short bullet points about SSE.",
  output: Output.text()
))

for try await delta in stream.textStream {
  print(delta, terminator: "")
}

let finalText = try await stream.text
```

## Documentation

Full docs live in [`content/docs/`](content/docs/).

## Project Status

AIKit is production-usable for early adopters, with active API iteration expected.

### What's not implemented yet

- `AIKitOpenAI` currently exposes provider/model entry points, but concrete language/embedding/image/speech/transcription model implementations still throw `AIKitError.notImplemented(...)`.

## Upstream Parity References

AIKit behavior is tracked against upstream references pinned as of February 24, 2026:

- AI SDK (`vercel/ai`) @ `73d5c5920e0fea7633027fdd87374adc9ba49743`: <https://github.com/vercel/ai/tree/73d5c5920e0fea7633027fdd87374adc9ba49743>
- OpenRouter provider (`OpenRouterTeam/ai-sdk-provider`) @ `7c043a085f796fa89b7181eedac356e8e53bf237`: <https://github.com/OpenRouterTeam/ai-sdk-provider/tree/7c043a085f796fa89b7181eedac356e8e53bf237>
- AI Elements (`vercel/ai-elements`) @ `10a5e65257b7f838ee3fe367713941f57b0e212c`: <https://github.com/vercel/ai-elements/tree/10a5e65257b7f838ee3fe367713941f57b0e212c>

## Roadmap (Short-Term)

- Continue AI SDK semantic parity work for `generateText` / `streamText`
- Complete OpenAI provider implementations
- Expand docs and migration guides
- Stabilize `AIKitElements` surface after early adopter feedback

## Contributing

Contributions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, standards, and review expectations.

Maintainer support is provided on a best-effort basis.

## Security

Please do not open public issues for vulnerabilities. See [`SECURITY.md`](SECURITY.md).

## License

MIT. See [`LICENSE`](LICENSE).
