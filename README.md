# AIKit

Swift-first, type-safe AI SDK for iOS and macOS apps.

AIKit is inspired by modern web AI frameworks (including Vercel AI SDK) and adapts those ideas into Swift APIs that feel native to Apple platforms, with strong typing, structured concurrency, and comprehensive tests.

## Why AIKit

- Swift-first API design (`generateText`, `streamText`, `Agent`, `ChatStore`)
- Type-safe outputs and tool calling
- Multi-provider architecture with shared wire/protocol types
- Streaming support for text, reasoning, tool input deltas, tool calls/results, and step boundaries
- Comprehensive provider and behavior test suite

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
- `AIKitOpenAI`
- `AIKitReplicate`
- `AIKitFal`
- `AIKitApple`
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

## Server Compatibility (Vercel AI SDK)

AIKit is designed to work well with a Node backend powered by Vercel AI SDK.

- Server: run `streamText(...)` and return `toUIMessageStreamResponse()`.
- Wire protocol: `text/event-stream` with `x-vercel-ai-ui-message-stream: v1` and terminal `data: [DONE]`.
- Client: use `ChatStore(remote: ...)` on iOS/macOS.
- Endpoint shape: `POST /api/chat` for send/regenerate, optional `GET /api/chat/:id/stream` for resume (`200` stream or `204` when no active stream).

This gives you a practical split: Vercel AI SDK on the server, AIKit on Apple clients.

## Documentation

Full docs live in [`content/docs/`](content/docs/).
For end-to-end server/client setup, see [`content/docs/06-advanced/04-node-server-chat-session.mdx`](content/docs/06-advanced/04-node-server-chat-session.mdx).

## Project Status

AIKit is production-usable for early adopters, with active API iteration expected.
AIKit does not provide strict parity guarantees with any JavaScript SDK.

### What's not implemented yet

- `AIKitOpenAI` currently exposes provider/model entry points, but concrete language/embedding/image/speech/transcription model implementations still throw `AIKitError.notImplemented(...)`.

## Roadmap (Short-Term)

- Expand server compatibility coverage for remote chat endpoints
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
