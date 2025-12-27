# OpenRouter Provider — Remaining TS Parity Gaps

This doc tracks remaining gaps between the vendored TypeScript provider in `openrouter-provider/` and the Swift implementation in `Sources/AIKitOpenRouter/`.

## What is already at parity (high confidence)

These are validated by ported Swift tests and/or fixes made during the migration:

- Streaming (chat + completion): SSE parsing, text deltas, reasoning deltas, reasoning ordering (reasoning before text), tool-input delta streaming, tool-call emission, file annotations accumulation, finish metadata, usage accounting (incl. token details + cost details).
- Streaming errors: structured error payload surfaced via `ModelStreamError` (message/type/code/param) and followed by a `.finish(.error)` part.
- Request headers: normalized to lowercase for comparison, `user-agent` suffix applied, provider + request headers merged.

## Unported TS test files (unverified parity)

These exist in `openrouter-provider/` but do not have full Swift equivalents yet, so parity is not proven:

### Chat

- `openrouter-provider/src/chat/convert-to-openrouter-chat-messages.test.ts`
  - Large matrix of edge cases around content parts, cache control, filenames, URL behaviors, reasoning_details preservation, etc.
- `openrouter-provider/src/chat/errors.test.ts`
  - HTTP 200 error payload handling and related error semantics.
- `openrouter-provider/src/chat/large-pdf-response.test.ts`
  - “Large PDF” failure payloads (HTTP 200 with `error`) and success responses including file annotation variants.
- `openrouter-provider/src/chat/payload-comparison.test.ts`
  - Exact request payload shape comparisons for large file inputs (structure-sensitive).
- `openrouter-provider/src/chat/file-parser-schema.test.ts`
  - Schema parsing coverage for FileParser annotations (realistic API shapes).
- `openrouter-provider/src/chat/index.test.ts`
  - Remaining `doGenerate` cases not yet mirrored with full strict equality assertions.

### Provider-wide / shared

- `openrouter-provider/src/tests/provider-options.test.ts`
  - Verifies `providerOptions.openrouter` passthrough into request body.
- `openrouter-provider/src/tests/usage-accounting.test.ts`
  - Non-streaming usage request flags and providerMetadata mapping (incl. conditional inclusion of token/cost detail sub-objects).

### Completion

- `openrouter-provider/src/completion/index.test.ts`
  - Remaining non-streaming (`doGenerate`) cases not yet mirrored with full strict equality assertions.

## Likely behavior gaps (to validate + implement if failing)

These are “probable” gaps based on the TS test taxonomy above; they need to be proven by porting tests:

- `providerOptions.openrouter` passthrough
  - TS expects `streamText(... providerOptions: { openrouter: {...} })` to merge those keys into the request body (chat + completion).
- Non-streaming usage accounting parity
  - TS validates request inclusion (`usage: { include: true }`) and exact `providerMetadata.openrouter.usage` mapping.
  - TS also validates “only include present token/cost detail sub-objects”.
- FileParser “old format” (`type: "file_annotation"`) behavior parity
  - Swift decodes it, but end-to-end behavior expectations (what becomes output content vs providerMetadata) are not yet asserted.
- Payload-shape exactness for file parts (PDF / large inputs)
  - TS has payload comparison tests ensuring the nested `file: { file_data: ... }` encoding and ordering match examples.

## Recommended next porting order

To close the biggest correctness risks first:

1. `openrouter-provider/src/tests/provider-options.test.ts`
2. `openrouter-provider/src/tests/usage-accounting.test.ts`
3. `openrouter-provider/src/chat/convert-to-openrouter-chat-messages.test.ts` (finish remaining cases)
4. `openrouter-provider/src/chat/errors.test.ts`
5. `openrouter-provider/src/chat/large-pdf-response.test.ts`
6. `openrouter-provider/src/chat/payload-comparison.test.ts`
7. `openrouter-provider/src/chat/file-parser-schema.test.ts`
8. Remaining `doGenerate` matrix in `openrouter-provider/src/chat/index.test.ts` + `openrouter-provider/src/completion/index.test.ts`

## Notes

- The Swift suite currently prioritizes streaming parity (per project direction). The remaining work is mostly request-shaping + conversion edge cases + non-stream usage behavior.
- When a TS test asserts strict JSON equality, Swift tests should also assert the exact `JSONValue` request body shape (including nested object structure), not just presence/contains checks.

