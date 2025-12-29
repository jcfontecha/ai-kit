# AIKit

Swift-first, type-safe client framework for building AI features on iOS/macOS, inspired by Vercel’s AI SDK (vendored under `vendored/ai-sdk/` for reference).

## Requirements

- iOS 15+
- macOS 12+
- Swift 5.10+

## Install (SwiftPM)

Add this repository as a Swift Package dependency, then depend on one of:

- `AIKit` (umbrella)
- `AIKitCore`, `AIKitProviders` (core APIs + provider protocols)
- Provider modules: `AIKitOpenRouter`, `AIKitOpenAI`, `AIKitReplicate`, `AIKitFal`

## Quickstart (generate)

```swift
import AIKit
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

let ai = AIClient(model: model)
let result = try await ai.generate("Write one sentence about Swift concurrency.")

print(result.text)
```

## Quickstart (stream)

```swift
import AIKit
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

let ai = AIClient(model: model)
let stream = ai.stream("Stream 3 short bullet points about SSE.")

for try await delta in stream.textStream {
  print(delta, terminator: "")
}
let finalText = try await stream.text
```

## Docs

Docs live under `content/docs/`.
