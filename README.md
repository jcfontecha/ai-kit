# AIKit

Swift-first, type-safe client framework for building AI features on iOS/macOS, inspired by Vercel’s AI SDK (vendored under `vendored/ai-sdk/` for reference).

## Requirements

- iOS 26+
- macOS 26+
- Swift 6.2+

## Install (SwiftPM)

Add this repository as a Swift Package dependency, then depend on one of:

- `AIKit` (app-facing)
- `AIKitProviders` (provider protocols + wire types)
- Provider modules: `AIKitOpenRouter`, `AIKitOpenAI`, `AIKitReplicate`, `AIKitFal`

## Quickstart (generate)

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

## Quickstart (stream)

```swift
import AIKit
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

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

## Docs

Docs live under `content/docs/`.
