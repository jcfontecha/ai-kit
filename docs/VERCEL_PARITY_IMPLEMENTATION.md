# Vercel Parity Progress

This document tracks the test-driven plan to align AIKit with the Vercel AI SDK behaviours we catalogued.

## Current Status

- ✅ **Gap analysis complete** – See `VERCEL_AI_SDK_ANALYSIS.md` for the architecture comparison.
- ✅ **Parity regression suite** – `AIChatVercelEdgeCasesTests.swift` now exercises:
  - Tool-call streaming lifecycle (start/delta/result exposure)
  - Stream result bookkeeping (tool calls/results, usage, finish reason)
  - Reasoning parts, redacted segments, reasoning signatures
  - Message annotations and stream data accumulation
- ✅ **Runtime plumbing landed**
  - `MessageContent` grew reasoning/annotation variants.
  - `StreamingMessageTracker` understands reasoning parts, streaming tool-call deltas, and tool results.
  - `StreamTextResult` exposes `streamDataValues`, enriched tool call/result accessors, and passes new metadata through to `StreamTextResponse`.
  - `AIClient+Streaming` parses both Vercel-style `stream.*` and OpenRouter-style `openrouter.*` additional outputs into typed structures.
- ✅ **Real provider verification**
  - `E2EMessageTrackingTests.testOpenAIStreamingWithToolCalls` (OpenAI) confirms streaming tool-call lifecycle without mocks.
  - `E2EOpenRouterTests.testOpenRouterStreamingIncludesReasoning` (OpenRouter `google/gemini-2.5-pro`) validates real reasoning fragments and annotations.
- 🔄 **Pending** – Attachments parity, resubmission safeguards, and additional provider test coverage (Anthropic, Google direct) remain open.

## Reference Map (Vercel SDK ↔︎ AIKit)

| Capability | Vercel sources | Closest AIKit areas | Notes |
| --- | --- | --- | --- |
| Streaming transport & parsing | `@ai-sdk/ui-utils/src/process-data-stream.ts`, `data-stream-parts.ts` | `AIClient+Streaming.swift`, `StreamingMessageTracker`, `ProviderChunk` | Parity achieved for textual, tool, reasoning, annotation, and stream-data parts (including OpenRouter `openrouter.*` keys). Attachments still pending. |
| Tool call reconstruction | `process-chat-response.ts` (lines ~220-344) | `AIClient+Streaming.swift`, `StreamTextResult`, `AIChat.streamResponse()` | Streaming builders now reconstruct tool-call arguments from deltas and expose them via tracker/result APIs. Need to fold resubmission logic into `AIChat`. |
| Message part normalisation | `@ai-sdk/ui-utils/src/fill-message-parts.ts`, `get-message-parts.ts` | `ChatMessage.orderedContent`, `StepMessageBuilder` | Reasoning/annotation parts are recorded, but attachments still live in side dictionaries. |
| Auto resubmission logic | `@ai-sdk/ui-utils/src/should-resubmit-messages.ts`, `extract-max-tool-invocation-step.ts`, `update-tool-call-result.ts` | `AIChat.streamResponse`, `StreamingMessageTracker`, `AIClient+TextGeneration.generateText` | Not yet ported. AIKit still relies on `maxSteps` without verifying step progression or completion thresholds. |
| Stream result API | `packages/ai/core/generate-text/stream-text-result.ts` | `StreamTextResult`, `StreamTextResponse` | Matches Vercel surface: `toolCalls`, `toolResults`, `streamData`. Need to expose typed accessors for reasoning/annotations if required. |
| Attachments lifecycle | `@ai-sdk/ui-utils/src/prepare-attachments-for-request.ts`, `call-chat-api.ts`, React `useChat.ts` | `AIChat+Advanced.sendMessage(withAttachments:)`, `messageAttachments` dictionaries | Still pending; attachments can desync when assistant message is replaced after streaming. |
| Reasoning telemetry | `process-chat-response.ts` (reasoning / redacted / signature handlers), `stream-text-result.ts` options | `ProviderChunk.additionalOutputs`, `MessageContent` reasoning cases | Reasoning, redacted segments, and signatures now flow through. Need follow-up for providers that emit alternate schemas (e.g. Anthropic). |

### Other Notable Files

- `VERCEL_AI_SDK_ANALYSIS.md`: Detailed architecture breakdown captured earlier (providers, tool flow, schema handling).
- `docs/RFC-AutomaticMessageTracking.md`: Design notes for `StreamingMessageTracker`; useful when aligning to Vercel’s `toResponseMessages`.
- `Tests/AIKitTests/StreamingAutoToolTests.swift`, `StreamingTests.swift`: Existing Swift coverage for streaming scenarios; useful baseline when expanding parity checks.
- `Sources/AIKit/Providers/OpenAIProvider.swift` (`processStreamChunk`): Already parses SSE deltas into `ProviderChunk` including streaming tool calls. Needs extension to emit reasoning/data codes into `additionalOutputs`.

## Patterns Observed in Vercel SDK

- **Single source of truth for messages**: All streaming mutations flow through `process-chat-response.ts`. The hook updates the SWR state incrementally and uses stable IDs plus revision stamps to force UI refreshes.
- **Structured stream protocol**: Prefix-based JSON lines ensure each event type is strongly typed (`DataStreamPart`). The parser is resumable and handles partial JSON across chunk boundaries.
- **Step-aware tool orchestration**: Each batch of tool calls is assigned a step index; auto-resubmit only occurs when the step advances and every invocation has a result.
- **Attachment pre-processing**: Client-side conversions (File → base64 Data URL) happen before hitting the API body to keep the messages array canonical.
- **Reasoning redaction**: Reasoning signatures and redacted segments are tracked separately so clients can render “hidden” steps but still show metadata.
- **Stream data channel**: Arbitrary JSON can be appended during streaming (`data` parts). Vercel exposes this via `chat.data` state so UIs can show side-panel updates or telemetry.

## Implementation Notes Collected

- `ProviderChunk.additionalOutputs` is currently a `[String: String]?`. For parity, we’ll likely map stream part codes into this structure temporarily, but long-term we should convert chunks into typed events similar to Vercel’s prefix codes.
- `StreamingMessageTracker` currently only stores text/tool calls/tool results. We’ll need to extend its `Step` structure (or replace it) to track reasoning segments, annotations, and attachments inline.
- `AIChat.streamResponse()` replaces assistant messages after streaming finishes (`response.messages` insertion). Attachment bookkeeping shortcuts (`messageAttachments`, `pendingToolAttachments`) will need refactoring once message parts become canonical.
- Tests currently reference helper functions `encodeJSON` and `extractValue` to inspect private state. Once implementation lands, we should expose proper accessors (e.g. `StreamTextResult.streamData`).
- Any new enum cases or model changes must remain `Codable`/`Sendable` to avoid regression in existing persistence tests (`ChatMessagePersistenceTests`).

## Next Steps

1. **Attachment + message-part integrity tests/implementation**
   - Mirror Vercel behaviour where attachments, tool results, and message replacements stay in sync.
   - Expected references: `@ai-sdk/ui-utils` attachment helpers and `fillMessageParts`.

2. **Resubmission safeguards**
   - Port `shouldResubmitMessages` semantics (step advancement, completed tool results, max step guard).
   - Tests should confirm the Swift client avoids infinite loops while auto-resubmitting when appropriate.

3. **Provider coverage expansion**
   - Add Anthropic/Gemini reasoning E2E runs to ensure their additional outputs survive the adapter layer.
   - Harden OpenRouter tests to assert stream-data payload structure once we flesh out attachment flow.

4. **Structured stream events (follow-up)**
   - Consider upgrading the chunk model from loosely typed `additionalOutputs` strings to a strong enum similar to Vercel’s `DataStreamPart` for long-term maintainability.

## Notes

- We’re deliberately keeping tests red during planning so implementation can follow the TDD loop.
- When adding new parity tests, annotate the motivating Vercel file/line range inside the test for traceability.
