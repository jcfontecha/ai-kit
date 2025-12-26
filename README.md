# AIKit

Swift-first, type-safe client framework for building AI features on iOS/macOS, inspired by Vercel’s AI SDK (vendored under `ai-sdk/` for reference).

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
import AIKitCore
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

let result = try await generateText(.init(
  model: model,
  prompt: "Write one sentence about Swift concurrency.",
  output: Output.Text()
))

print(try result.output)
```

## Quickstart (stream)

```swift
import AIKitCore
import AIKitOpenRouter

let openrouter = createOpenRouter(.init(apiKey: "<OPENROUTER_API_KEY>"))
let model = openrouter.chat("openai/gpt-4o-mini")

let stream = streamText(.init(
  model: model,
  prompt: "Stream 3 short bullet points about SSE.",
  output: Output.Text()
))

for try await delta in stream.textStream {
  print(delta, terminator: "")
}
let finalText = try await stream.text
```

## Docs

Start here: `docs/README.md`

