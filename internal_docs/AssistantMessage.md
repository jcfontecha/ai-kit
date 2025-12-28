# AssistantMessage (AIKitElements)

`AssistantMessage` is an assistant “message body” primitive that renders interleaved `AIKit.ChatMessagePart`:

- text parts
- reasoning parts (optional disclosure)
- tool parts (including approvals) + tool-specific renderers
- sources + file attachments

This is the main home for tool rendering complexity. Compose your own container (e.g. `Conversation`) around it.

## Import

```swift
import AIKitElements
import AIKit
```

## API

### Minimal

```swift
AssistantMessage(parts: message.parts)
```

### Custom assistant text rendering (e.g. Markdown)

```swift
AssistantMessage(parts: message.parts) { text in
  Markdown(text)
}
```

## Configuration (SwiftUI-style modifiers)

These modifiers set environment values, so you can apply them to a single message or to a higher-level container.

### Reasoning

```swift
AssistantMessage(parts: message.parts)
  .assistantMessageShowsReasoning(false)
```

### Tool approvals

If you want the default tool card approval buttons to work, provide a handler:

```swift
AssistantMessage(parts: message.parts)
  .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
    session.addToolApprovalResponse(approvalID: approvalID, approved: approved, reason: reason)
  }
```

### Tool rendering

You can either set an entire map:

```swift
AssistantMessage(parts: message.parts)
  .assistantMessageToolRenderers([
    "fetch_weather_data": { ctx in
      AnyView(WeatherToolView(tool: ctx.tool, isLoading: ctx.isLoading))
    }
  ])
```

…or register a single tool renderer (merges with any existing renderers in the environment):

```swift
AssistantMessage(parts: message.parts)
  .assistantMessageToolRenderer("fetch_weather_data") { ctx in
    WeatherToolView(tool: ctx.tool, isLoading: ctx.isLoading)
  }
```

Tool renderers receive `ToolRenderContext`:

- `tool`: `ChatToolPart`
- `isLoading`: `Bool` (derived from `tool.state`)
- `sendApproval(approved:reason:)`: calls the approval handler for this tool (if an approval id exists)

## Default tool UI

If you do not provide a custom renderer for `tool.toolName`, `AssistantMessage` renders a collapsible tool card showing:

- status (“Pending”, “Running”, “Awaiting approval”, “Completed”, “Error”, “Denied”)
- parameters (from `tool.input` or `tool.rawInput`)
- result/error (from `tool.output` / `tool.state`)
- approval actions when `tool.state` is `.approvalRequested`
