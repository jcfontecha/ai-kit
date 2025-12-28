# AIKitElements — Conversation (Parity Checklist)

This document tracks the SwiftUI `Conversation` parity goals vs `ai-elements`’ web `Conversation`.

## Manual QA

- Auto-scroll when at bottom: stream/append messages and confirm the view stays pinned to the bottom.
- No auto-scroll when not at bottom: scroll up, stream/append messages, confirm scroll position is preserved and the scroll button appears.
- Scroll button: when visible, tapping it scrolls to bottom and the button disappears.
- Resize behavior: change composer height / rotate device / resize macOS window and confirm pinned state behaves correctly.
- Empty state: with no messages, confirm `ConversationEmptyState` default and customized title/description/icon render correctly.
- Accessibility: VoiceOver reads messages in a sensible order; scroll button has a label (“Scroll to bottom”).

