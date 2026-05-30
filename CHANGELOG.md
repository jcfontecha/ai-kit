# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once stable.

## [Unreleased]

### Added

- `AIKitOpenAI` model implementations: Responses API and Chat Completions language
  models, embeddings, image generation (incl. multipart edits), transcription, and speech.
- `dynamicTool(...)`: runtime-schema tools registered alongside statically-typed `ToolSpec`.
- `AIKitMCP`: Model Context Protocol client (Streamable HTTP, JSON-RPC) exposing MCP
  server tools as dynamic tools.
- `AIKitElements` components matching Vercel AI Elements: `ShimmerText`, `Confirmation`,
  `Suggestions`, `ContextUsage`, `ModelSelector`, `SourcesGroup`, `InlineCitation`,
  `AgentTaskView`, `ChainOfThought`, `PlanView`, and an `assistantMessageDataRenderer`
  hook for rendering custom `data-*` parts.

### Changed

- `TranscriptionRequest` gains `mediaType` and `providerOptions`; `SpeechRequest` gains
  `providerOptions` (additive).

## [0.1.0] - 2026-02-24

### Added

- Initial public release of AIKit Swift package products:
  - `AIKit`
  - `AIKitProviders`
  - `AIKitElements`
  - `AIKitOpenRouter`
  - `AIKitOpenAI`
  - `AIKitReplicate`
  - `AIKitFal`
  - `AIKitApple`
  - `AIKitMacro`
- Core APIs including `generateText`, `streamText`, tool loop support, approvals, and chat/session surfaces.
- Provider implementations for OpenRouter, Replicate, and Fal.
- Parity-oriented tests across core and provider modules.
- Public documentation and contribution/security/community policy docs.

### Known limitations

- `AIKitOpenAI` currently exposes provider/model surfaces, but concrete model implementations are not yet available and throw `AIKitError.notImplemented(...)`.
- APIs may still evolve while the project is pre-1.0.

[0.1.0]: https://github.com/jcfontecha/ai-kit/releases/tag/v0.1.0
