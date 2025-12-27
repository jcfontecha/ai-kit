# AIKit Elements Proposal (SwiftUI / UIKit)

This document proposes a native, reusable UI component set—**AIKit Elements**—inspired by the vendored **AI Elements** library (`ai-elements/`) and designed to work *natively* with AIKit’s existing runtime types and semantics (streaming, tools, approvals, sources, etc.).

The goal is to provide **composable primitives** (not a monolithic “Chat UI”) that integrate cleanly with:

- `ChatSession` / `ChatMessage` for “useChat-style” interactive sessions (`Sources/AIKitCore/ChatSession/...`)
- `streamText` / `TextStreamPart` for headless streaming scenarios (`Sources/AIKitCore/Streaming/StreamText.swift`)

---

## 1) Scope and goals

### Goals

- Provide **SwiftUI-first** components (iOS 15+, macOS 12+) aligned with the package platforms in `Package.swift`.
- Be **AIKit-native**: components consume AIKit types directly (e.g. `ChatMessage`, `ChatToolPart`) rather than introducing a parallel “UI message” model.
- Preserve AI SDK semantics where applicable:
  - tool states (`input-streaming`, `input-available`, `output-*`, approvals) map naturally to `ChatToolPart.State` (`Sources/AIKitCore/ChatSession/ChatMessage.swift`).
  - approvals flow through `ChatSession.addToolApprovalResponse(...)` (`Sources/AIKitCore/ChatSession/ChatSession.swift`).
  - streaming-friendly rendering for text/reasoning and “append-only” updates.
- Keep components **composable** (AI Elements style): small building blocks like `Conversation`, `Message`, `PromptInput`, `Tool`, `Confirmation`, etc.

### Non-goals (v0)

- Shipping a full design system. Provide sensible defaults + theming hooks, but avoid an opinionated “app framework”.
- Full parity with AI Elements workflow/ReactFlow components (canvas/node/edge) in the first iteration; those are large and can be staged later.
- Recreating web-only behavior (DOM drag-drop semantics, Radix-specific interactions) 1:1; aim for native equivalents.

---

## 2) What AI Elements actually is (reference inventory)

AI Elements is a library of composable React components for AI-native UIs, including:

- Chatbot: `conversation`, `message`, `prompt-input`, `sources`, `reasoning`, `tool`, `confirmation`, `suggestion`, `context`, …
- Vibe-coding: `web-preview`, `artifact`
- Workflow: `canvas`, `node`, `edge`, `connection`, `controls`, `panel`, `toolbar`
- Utilities: `code-block`, `loader`, `shimmer`, `checkpoint`, `inline-citation`, …

Reference entry points:

- Components list: `ai-elements/README.md`
- Implementations: `ai-elements/packages/elements/src/*.tsx`
- Component docs: `ai-elements/apps/docs/content/docs/components/**`

The main architectural pattern to carry over:

- **Primitives + subcomponents** (composition over configuration). For example:
  - `Conversation`, `ConversationContent`, `ConversationEmptyState`, `ConversationScrollButton` (`ai-elements/packages/elements/src/conversation.tsx`)
  - `Tool`, `ToolHeader`, `ToolContent`, `ToolInput`, `ToolOutput` (`ai-elements/packages/elements/src/tool.tsx`)
  - `Confirmation` with conditional subviews for approval states (`ai-elements/packages/elements/src/confirmation.tsx`)

---

## 3) Proposed package layout (SPM)

Add a new optional UI target:

- Target: `AIKitElements`
  - SwiftUI primitives + small UIKit bridges where needed (e.g. text views / markdown).
  - Depends on `AIKitCore` (for `ChatSession`, `ChatMessage`, `JSONValue`, etc.).
- Product: `.library(name: "AIKitElements", targets: ["AIKitElements"])`

Optional follow-ups (later):

- `AIKitElementsUIKit` (UIKit-only wrappers and hosting helpers)
- `AIKitElementsWorkflow` (graph/canvas equivalents)

Rationale: keep AIKit Core provider-agnostic and “headless”, while `AIKitElements` is explicitly UI-focused.

---

## 4) Component mapping (AI Elements → AIKit Elements)

Below is the recommended v0 component set. Names are suggestions; the important part is **behavior + composition style**.

### Conversation

AI Elements reference: `ai-elements/packages/elements/src/conversation.tsx`

Proposed SwiftUI primitives:

- `Conversation` (scroll container with “stick to bottom” behavior)
- `ConversationContent` (vertical stack wrapper, spacing/padding)
- `ConversationEmptyState` (icon + title + description)
- `ConversationScrollToBottomButton` (appears when user is not at bottom)

Notes:

- SwiftUI needs a native “stick-to-bottom” implementation (e.g. `ScrollViewReader` + “isAtBottom” tracking).

### Message + attachments + markdown response

AI Elements reference: `ai-elements/packages/elements/src/message.tsx`

Proposed SwiftUI primitives:

- `Message` (role-aligned container: `.user` trailing vs assistant leading)
- `MessageBubble` / `MessageContent` (styling)
- `MessageActions` / `MessageActionButton`
- `MessageAttachments` / `MessageAttachment` (images vs generic files)
- `MessageResponse(markdown:)` (streaming-friendly markdown rendering)

AIKit-native data model:

- `ChatMessage.role` and `ChatMessage.parts` (`Sources/AIKitCore/ChatSession/ChatMessage.swift`)
- `ChatMessagePart.text`, `.reasoning`, `.file`, `.sourceURL`, `.sourceDocument`, `.tool`, `.data`

Markdown considerations:

- Keep the renderer pluggable (a `MarkdownRendering` protocol) so apps can choose:
  - lightweight: `AttributedString(markdown:)` where sufficient
  - heavier: a custom markdown pipeline for tables/code/math if needed (mirrors AI Elements’ Streamdown usage)

### Prompt input (text + attachments)

AI Elements reference: `ai-elements/packages/elements/src/prompt-input.tsx`

Proposed SwiftUI primitives:

- `PromptInput` (composable container)
- `PromptInputTextEditor` (multi-line, submit behavior)
- `PromptInputAttachmentsStrip`
- `PromptInputToolbar` slot (buttons, model selector, etc.)
- `PromptInputSubmitButton` (send vs stop; mirrors “status” usage in AI Elements docs)

AIKit-native output:

- Prefer emitting `ChatDraftMessage` (role + parts) (`Sources/AIKitCore/ChatSession/ChatDraftMessage.swift`) so apps can do:
  - `await session.send(draft, options: ...)`

Attachments (native equivalents vs web):

- iOS: `PhotosPicker`, `fileImporter`, pasteboard images/files
- model shape: use `ChatMessagePart.file(ChatFilePart)` with `DataContent` (`Sources/AIKitProviders/Model/Content.swift`)

### Tool presentation

AI Elements reference: `ai-elements/packages/elements/src/tool.tsx`

Proposed SwiftUI primitives:

- `ToolDisclosure` (collapsible)
- `ToolHeader` (tool name/title + status badge)
- `ToolInputView` (formatted JSON)
- `ToolOutputView` (JSON / markdown / custom content)

AIKit-native source of truth:

- `ChatToolPart` + `ChatToolPart.State` + `ChatToolPart.approval` (`Sources/AIKitCore/ChatSession/ChatMessage.swift`)

### Confirmation (tool approvals)

AI Elements reference: `ai-elements/packages/elements/src/confirmation.tsx`

Proposed SwiftUI primitives:

- `ToolApprovalBanner(tool:onRespond:)` with conditional content slots:
  - `ApprovalRequestedContent`
  - `ApprovalAcceptedContent`
  - `ApprovalRejectedContent`
  - `ApprovalActions`

AIKit-native wiring:

- Call `await session.addToolApprovalResponse(approvalID:approved:reason:)` (`Sources/AIKitCore/ChatSession/ChatSession.swift`)

### Reasoning

AI Elements reference: `ai-elements/packages/elements/src/reasoning.tsx`

Proposed SwiftUI primitives:

- `ReasoningDisclosure(isStreaming:content:)` with:
  - auto-open on streaming start
  - optional auto-close after streaming end (AI Elements uses a delay)

AIKit-native source of truth:

- `ChatMessagePart.reasoning(ChatReasoningPart)` has `state: streaming|done` (`Sources/AIKitCore/ChatSession/ChatMessage.swift`)

### Sources + inline citations

AI Elements references:

- `ai-elements/packages/elements/src/sources.tsx`
- `ai-elements/packages/elements/src/inline-citation.tsx`

Proposed SwiftUI primitives:

- `SourcesDisclosure(count:content:)`
- `SourceRow(title:url:)`
- Optional: `InlineCitationPopover` for “in-text” citations where the markdown renderer can surface them

AIKit-native source of truth:

- `ChatMessagePart.sourceURL(ChatSourceURLPart)`
- `ChatMessagePart.sourceDocument(ChatSourceDocumentPart)`

### Suggestions, loader, shimmer, code block, context

AI Elements references:

- `suggestion`: `ai-elements/packages/elements/src/suggestion.tsx`
- `loader`: `ai-elements/packages/elements/src/loader.tsx`
- `shimmer`: `ai-elements/packages/elements/src/shimmer.tsx`
- `code-block`: `ai-elements/packages/elements/src/code-block.tsx`
- `context`: `ai-elements/packages/elements/src/context.tsx`

Proposed SwiftUI equivalents:

- `SuggestionChips` / `SuggestionChip`
- `LoaderIndicator`
- `ShimmerText`
- `CodeBlockView(code:language:)` (syntax highlighting as a pluggable dependency)
- `ContextUsagePopover` (maps to AIKit `Usage` where available: `Sources/AIKitProviders/Model/Usage.swift`)

Note: AI Elements “cost” calculation is web-specific (`tokenlens`); AIKit can show usage counts without pricing, unless we add an explicit pricing model mapping.

---

## 5) Integration style: “primitives first”, optional `ChatView`

AI Elements encourages apps to assemble UIs from primitives. AIKit Elements should mirror that by providing:

1) **Primitive Views** that take plain values (e.g. `ChatMessage`, `ChatToolPart`)
2) An optional **reference composition** `ChatView(session:)` that wires:
   - conversation list
   - message rendering by `ChatMessagePart` type
   - prompt input → `ChatDraftMessage`
   - tool approvals → `ChatSession.addToolApprovalResponse`

Important: `ChatView` should be a thin composition so apps can replace any part.

---

## 6) Theming and customization

Match AI Elements’ “copy into your codebase and edit” spirit, but in Swift:

- Provide a small `AIKitElementsTheme` (colors, typography, spacing) via SwiftUI `Environment`.
- Keep default visuals minimal and native (system fonts, dynamic type, system colors).
- Make layout/styling overridable through:
  - environment theme
  - view builder slots (e.g. custom tool output renderer)
  - minimal configuration types (avoid a second UI DSL)

---

## 6.1) Liquid Glass styling spec (SwiftUI first; iOS/macOS 26+)

This section defines how AIKit Elements should blend with Apple’s Liquid Glass design language while remaining readable and performant in chat-heavy views.

### Principles (rules of thumb)

- **Hierarchy:** Glass is for **chrome/overlays**, not for primary content. In chat UIs, avoid glass behind long-form markdown, code blocks, or dense message text.
- **Dynamism:** Tappable controls that sit on glass should use **interactive glass** so the material “lights up” on touch.
- **Consistency:** Prefer system surfaces that auto-adopt Liquid Glass (navigation, toolbars, tab bars) and only add custom glass where we build custom chrome.

### Allowed glass surfaces (v0)

Use glass here:

- `PromptInput` container surface (single unified surface behind the whole input bar)
- Floating `ConversationScrollToBottomButton` (circle)
- Tool/approval UI (`ToolDisclosure`, `ToolApprovalBanner`) as *one surface per panel*
- Popovers/cards (`SourcesDisclosure`, inline citation popovers)
- “Secondary chrome” panels (model selector sheet, quick-action bars)

Avoid glass here:

- The main `Conversation` scroll content background
- `MessageResponse` rendering area (markdown/code/math)
- Repeated list cells / every message bubble (excessive blur stacking and contrast loss)

### Shape + corner radius tokens

Use consistent shapes so the UI reads as system-native:

- **Floating buttons:** `.circle` (e.g. scroll-to-bottom, small icon actions)
- **Input bars / toolbars:** `.capsule` or `.rect(cornerRadius:)`
- **Panels (tools, confirmations, popovers):** `.rect(cornerRadius:)` with a consistent radius (recommend starting at `20`)

### Tint guidelines

Tint is a last-mile tool for contrast, not branding-by-default:

- Default: **untinted** regular glass
- If contrast is poor over variable backgrounds, apply a **subtle tint** (e.g. `0.05–0.15` opacity depending on light/dark mode)
- Avoid strong tint unless the element is a prominent, focused panel (e.g. destructive approval banners)

### Interactivity

- Use `.interactive()` for:
  - primary actions in the prompt input toolbar
  - floating controls (scroll-to-bottom)
  - approval action buttons
- Avoid `.interactive()` for large, non-interactive panels (it can create distracting highlights).

### Grouping and unions (performance + visual cohesion)

- Wrap clusters of adjacent glass controls in `GlassEffectContainer` to reduce compositing overhead and encourage unified lighting.
- If a row of adjacent pill buttons should read as one continuous surface, use `glassEffectUnion(id:namespace:)` with a shared id/namespace for the participating views, inside a `GlassEffectContainer`.
- Prefer “one glass background + normal content inside” over nesting multiple glass layers.

### Morphing transitions (state changes)

For expand/collapse (e.g. prompt input expanding to show attachments or tool panel expanding):

- Tag the collapsed and expanded glass surfaces with the same `glassEffectID(_:in:)`
- Use `.glassEffectTransition(.matchedGeometry)` for a single, continuous morph

### Backward compatibility + accessibility

- Provide **progressive enhancement**:
  - iOS/macOS 26+: Liquid Glass
  - iOS/macOS 25 and earlier: material blur (`.regularMaterial`) or solid surfaces, matching the element’s role
- Respect **Reduce Transparency**:
  - when enabled, use a mostly-opaque system background fill instead of glass/material

---

## 7) Testing strategy

Prefer tests that validate “AI-native UI behavior” without brittle pixel snapshots:

- Snapshot-style tests of **render models** (e.g. a deterministic list of rendered rows/sections derived from `ChatMessage.parts`).
- Behavioral tests around:
  - “stick to bottom” state transitions
  - approval request → respond → auto-submit policies (where applicable via `ChatSession.sendAutomaticallyWhen`)

UI screenshot tests can be an optional later layer, but are not required for v0.

---

## 8) Recommended delivery plan (phased)

### Phase 1 (Chat essentials)

- `Conversation*` (scroll + scroll-to-bottom button)
- `Message*` (role styling + attachments)
- `MessageResponse` (pluggable markdown rendering)
- `Tool*` + `Confirmation*` (tool states + approvals)
- `PromptInput*` (text + file picking; emit `ChatDraftMessage`)

### Phase 2 (AI-native extras)

- `Reasoning*`
- `Sources*` (+ optional inline citation UI if supported by markdown pipeline)
- `Suggestion*`
- `ContextUsage*` (usage popover)

### Phase 3 (Vibe-coding + workflow)

- `WebPreview*` (native `WKWebView` + optional console presentation)
- `Artifact*`
- Evaluate a native graph/canvas story (`Canvas/Node/Edge/...`) based on actual product needs.
