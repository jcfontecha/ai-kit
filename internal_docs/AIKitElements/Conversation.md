# AIKitElements — Conversation (Parity Checklist)

This document tracks the SwiftUI `Conversation` parity goals vs `ai-elements`’ web `Conversation`.

## Manual QA

- Auto-scroll when at bottom: stream/append messages and confirm the view stays pinned to the bottom.
- No auto-scroll when not at bottom: scroll up, stream/append messages, confirm scroll position is preserved.
- Optional "pin new user message to top": enable `conversationAnchorsNewUserMessagesToTop(true)`, send a user message, confirm it scrolls to the top and only switches back to stick-to-bottom once the assistant stream overflows.
- Resize behavior: change composer height / rotate device / resize macOS window and confirm pinned state behaves correctly.
- Prompt input caret: type a multi-line draft, move the caret to the middle, and confirm it does not jump to the end while typing or during layout updates (composer caps at ~8 lines, then scrolls internally).
- Empty state: with no messages, confirm `ConversationEmptyState` default and customized title/description/icon render correctly.
- Accessibility: VoiceOver reads messages in a sensible order.

## Debugging Log — Scroll Indicator Jitter (Top Bounce)

### Symptom

- When scrolling all the way to the top and triggering the bounce, the scroll indicator thumb animates in a visibly “jagged/jumpy” way (not the normal iOS overscroll thumb scaling).

### Repro

- Build/run `AIKitElementsDemoApp`, open `OpenRouterChatDemoView`, scroll up to the top, then bounce.

### What We Think Is Happening (Hypothesis)

- Something is causing the `ScrollView`’s effective content size / scrollable range to change during (or immediately around) the bounce animation.
- That in turn makes the scroll indicator repeatedly recompute its thumb size/position in quick succession, which reads as “glitchy”.

### Changes We Made That Did NOT Fix It

- Switching between “minimal” and “more animated” auto-scroll approaches:
  - `ScrollViewReader` + `ScrollView` + `LazyVStack` + bottom sentinel (`Color.clear.id(...)`) with `isAtBottom` driven by sentinel `onAppear/onDisappear`.
  - Scroll triggers on: `messages.count`, streaming updates, `status == .streaming`, and `bottomInset` changes.
- Adding/removing the scroll-to-bottom arrow button overlay (and related state).
- Throttling streaming scroll-to-bottom (e.g. 50ms task-based throttle) and/or changing scroll animations.
- Animating vs not animating the bottom sentinel height (`bottomInset`) and gating animations based on pinned state.
- Attempting to “fix” the indicator by disabling bounce (rejected; not acceptable for UX and still didn’t address the underlying jitter).
- Pixel-snapping the composer height measurement and ignoring tiny deltas (helpful for reducing layout churn in general, but did not eliminate the top-bounce jitter in our testing).

### Changes We Made That WERE Necessary (But Not Related To The Jitter)

- Bottom inset not applying initially:
  - Root cause: the chat composer height measurement wasn’t reliably propagating through `safeAreaInset` in some configurations.
  - Fix: measure composer height directly via `GeometryReader` and write into the `height` binding from `.onAppear` / `.onChange(of: proxy.size.height)`.

## Next Things To Test (Narrow Down Root Cause)

These are meant as controlled A/B experiments (change one variable at a time):

1. `LazyVStack` vs `VStack`
   - Result: swapping `LazyVStack` → `VStack` eliminated the top-bounce scroll indicator jitter.
   - Working hypothesis: `LazyVStack`’s incremental realization/measurement during edge bounce causes content-size churn, which makes the indicator thumb recompute repeatedly.
   - Next: keep `VStack`, but add paging (render only the last N messages + “load older” sentinel) to preserve performance on large histories.
2. Remove `scrollEdgeEffectStyle(.hard, for: .bottom)`
   - Especially on iOS 26+, this modifier changes edge behavior; verify whether it affects indicator stability even when the jitter is observed at the *top* edge.
3. Remove `scrollDismissesKeyboard(.interactively)`
   - Verify whether interactive keyboard dismissal is causing scroll view geometry updates during bounce.
4. Remove the bottom inset animation entirely
   - Keep bottom inset itself, but ensure height changes are not animated by SwiftUI layout during unrelated scroll interactions.
5. Force a constant bottom inset
  - Temporarily hardcode `.conversationBottomOverlayHeight(...)` to a constant and stop measuring composer height, to see if composer measurement is fluctuating during bounce.
