# Vercel Tool Parity Harness

This harness records canonical Vercel AI SDK tool-calling behaviour and compares it with AIKit executions.

## Workflow

1. Generate fixtures with Vercel AI SDK:
   ```bash
   scripts/vercel-tool-parity.sh
   ```
   - Runs `tools/vercel-comparison/run-scenarios.mjs` to regenerate JSON fixtures under `Tests/Fixtures/VercelToolParity/`.
   - Invokes the offline parity tests (`VercelToolParityTests`) for each scenario.

2. Targeted updates:
   ```bash
   scripts/vercel-tool-parity.sh auto-single-tool-call
   ```
   Pass scenario names to regenerate and re-test a subset. The default batch includes `auto-single-tool-call`, `multi-tool-handoff`, `tool-json-result`, `sequential-image-tools`, and `interleaved-image-tools`.

3. Live comparisons (hits the OpenAI Chat API – requires `OPENAI_API_KEY` in the environment or `Config.plist`):
   ```bash
   scripts/vercel-tool-parity.sh --live
   ```
   You can scope to specific scenarios, e.g. `--live auto-single-tool-call`.
   Under the hood this exercises `RealVercelToolParityTests`, which executes both the Vercel AI SDK and AIKit against the real model and compares tool sequences/results.

## Scenarios

Fixtures currently cover:
- `auto-single-tool-call`: single tool invocation with automatic execution.
- `multi-tool-handoff`: sequential tool calls chaining search and weather tools.
- `tool-json-result`: tools returning structured JSON payloads.
- `tool-execution-error`: tool failure propagated as a generation error.
- `sequential-image-tools`: multiple tool calls resolved before the assistant sends its final message.
- `interleaved-image-tools`: assistant interleaves partial narration with additional tool calls, exercising ordering of call/result pairs.

Each fixture stores:
- Model responses used by the fixture provider.
- Canonical Vercel output (messages, steps, usage, tool results).
- Recorded tool execution arguments and results for deterministic replay on the Swift side.

## Swift Test Suite

`Tests/AIKitTests/VercelToolParityTests.swift` loads the fixtures, replays the scenario against AIKit, and compares:
- Final text, finish reason, and usage totals.
- Assistant/tool message formatting (including tool calls and results).
- Normalised step sequence (tool call chaining vs. final answer steps).

If the comparison fails the test output highlights the first difference for quick triage.

## Live Test Coverage

`Tests/AIKitTests/VercelParity/RealVercelToolParityTests.swift` runs the same scenarios against the real OpenAI API via the Vercel SDK and AIKit. The live suite focuses on structural parity:

- Tool call ordering and canonical arguments.
- Tool results returned to the model.
- Presence of final assistant messages incorporating the tool output.

Token usage and free-form assistant wording are printed for manual inspection (the services occasionally diverge even with deterministic settings). The suite skips scenarios automatically if the API request times out.

You can invoke specific live scenarios directly, e.g.:

```bash
swift test --filter RealVercelToolParityTests/testMultiToolHandoff
```
