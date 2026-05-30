import SwiftUI

typealias ComponentID = String

enum ComponentCategory: String, CaseIterable, Identifiable {
  case chatbot
  case utilities
  case vibeCoding
  case workflow

  var id: String { rawValue }

  var title: String {
    switch self {
    case .chatbot: "Chatbot"
    case .utilities: "Utilities"
    case .vibeCoding: "Vibe Coding"
    case .workflow: "Workflow"
    }
  }
}

struct ComponentVariant: Identifiable {
  var id: String
  var title: String
  var description: String?
  var build: @MainActor () -> AnyView
}

struct ComponentDefinition: Identifiable {
  var id: ComponentID
  var category: ComponentCategory
  var name: String
  var summary: String
  var variants: [ComponentVariant]
}

enum ComponentCatalog {
  static func component(id: ComponentID) -> ComponentDefinition? {
    all.first(where: { $0.id == id })
  }

  static func components(in category: ComponentCategory, matching query: String) -> [ComponentDefinition] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    return all
      .filter { $0.category == category }
      .filter { component in
        guard trimmedQuery.isEmpty == false else { return true }
        let haystack = "\(component.name) \(component.summary)".lowercased()
        return haystack.contains(trimmedQuery.lowercased())
      }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private static let all: [ComponentDefinition] = [
    .init(
      id: "conversation",
      category: .chatbot,
      name: "Conversation",
      summary: "Scroll container + stick-to-bottom patterns",
      variants: [
        .init(id: "conversation/basic", title: "Basic", description: "Message list with a floating scroll-to-bottom control") {
          AnyView(ConversationDemoView())
        },
        .init(id: "conversation/perf", title: "Performance", description: "Stress-test with many messages + tool calls") {
          AnyView(ConversationPerfDemoView())
        },
      ]
    ),
    .init(
      id: "message",
      category: .chatbot,
      name: "Message",
      summary: "User/assistant message layout + bubble defaults",
      variants: [
        .init(id: "message/basic", title: "Basic", description: "Simple user + assistant messages") {
          AnyView(MessageDemoView())
        },
      ]
    ),
    .init(
      id: "assistant-message",
      category: .chatbot,
      name: "Assistant Message",
      summary: "Interleaved assistant parts (text, reasoning, tools, sources, files)",
      variants: [
        .init(id: "assistant-message/kitchen-sink", title: "Kitchen Sink", description: "Shows as many supported parts as possible") {
          AnyView(AssistantMessageDemoView())
        },
      ]
    ),
    .init(
      id: "prompt-input",
      category: .chatbot,
      name: "Prompt Input",
      summary: "Composer bar (text + toolbar actions) as a single glass surface",
      variants: [
        .init(id: "prompt-input/idle", title: "Idle", description: "Empty composer") {
          AnyView(PromptInputDemoView(mode: .idle))
        },
        .init(id: "prompt-input/typing", title: "Typing", description: "Text entry + enabled send") {
          AnyView(PromptInputDemoView(mode: .typing))
        },
        .init(id: "prompt-input/streaming", title: "Streaming", description: "Stop button state") {
          AnyView(PromptInputDemoView(mode: .streaming))
        },
        .init(id: "prompt-input/with-attachments", title: "With Input Attachment", description: "Composer with attachments above the field") {
          AnyView(PromptInputDemoView(mode: .withAttachments))
        },
        .init(id: "prompt-input/bottom-bar-idle", title: "Bottom Bar (Idle)", description: "Tap the field to show expanded buttons") {
          AnyView(PromptInputDemoView(mode: .bottomBarIdle))
        },
        .init(id: "prompt-input/bottom-bar-typing", title: "Bottom Bar (Typing)", description: "Tap the field to show expanded buttons") {
          AnyView(PromptInputDemoView(mode: .bottomBarTyping))
        },
        .init(id: "prompt-input/bottom-bar-streaming", title: "Bottom Bar (Streaming)", description: "Stop button state + expanded buttons") {
          AnyView(PromptInputDemoView(mode: .bottomBarStreaming))
        },
        .init(id: "prompt-input/bottom-bar-with-attachments", title: "Bottom Bar (With Attachments)", description: "Attachments + expanded buttons") {
          AnyView(PromptInputDemoView(mode: .bottomBarWithAttachments))
        },
      ]
    ),
    .init(
      id: "tool",
      category: .chatbot,
      name: "Tool",
      summary: "Tool call presentation (input/output/error/denied)",
      variants: [
        .init(id: "tool/states", title: "States", description: "Pending, running, completed, error") {
          AnyView(ToolDemoView())
        },
      ]
    ),
    .init(
      id: "confirmation",
      category: .chatbot,
      name: "Confirmation",
      summary: "Tool approval requested/accepted/rejected",
      variants: [
        .init(id: "confirmation/basic", title: "Approval", description: "Approval banner with actions") {
          AnyView(ConfirmationDemoView())
        },
      ]
    ),
    .init(
      id: "shimmer-text",
      category: .chatbot,
      name: "Shimmer Text",
      summary: "Single-line shimmering streaming/thinking label",
      variants: [
        .init(id: "shimmer-text/basic", title: "Basic", description: "Shimmering status lines") {
          AnyView(ShimmerTextDemoView())
        },
      ]
    ),
    .init(
      id: "suggestions",
      category: .chatbot,
      name: "Suggestions",
      summary: "Horizontal row of tappable starter-prompt pills",
      variants: [
        .init(id: "suggestions/basic", title: "Basic", description: "Scrollable suggestion pills") {
          AnyView(SuggestionsDemoView())
        },
      ]
    ),
    .init(
      id: "model-selector",
      category: .chatbot,
      name: "Model Selector",
      summary: "Compact composer model picker (glass pill + menu)",
      variants: [
        .init(id: "model-selector/basic", title: "Basic", description: "Menu-backed model picker") {
          AnyView(ModelSelectorDemoView())
        },
      ]
    ),
    .init(
      id: "reasoning",
      category: .chatbot,
      name: "Reasoning",
      summary: "Disclosure for streaming reasoning (header can be glass; body should be readable)",
      variants: [
        .init(id: "reasoning/basic", title: "Basic", description: "Collapsible reasoning panel") {
          AnyView(ReasoningDemoView())
        },
      ]
    ),
    .init(
      id: "sources",
      category: .chatbot,
      name: "Sources",
      summary: "Collapsible sources list / popover-friendly rows",
      variants: [
        .init(id: "sources/basic", title: "Basic", description: "Used N sources + list") {
          AnyView(SourcesDemoView())
        },
      ]
    ),
    .init(
      id: "inline-citation",
      category: .chatbot,
      name: "Inline Citation",
      summary: "Popover for in-text citations",
      variants: [
        .init(id: "inline-citation/basic", title: "Basic", description: "Citation token → popover") {
          AnyView(InlineCitationDemoView())
        },
      ]
    ),
    .init(
      id: "agent-task",
      category: .chatbot,
      name: "Agent Task",
      summary: "Collapsible task with sub-steps",
      variants: [
        .init(id: "agent-task/basic", title: "Basic", description: "Title + step statuses") {
          AnyView(AgentTaskDemoView())
        },
      ]
    ),
    .init(
      id: "chain-of-thought",
      category: .chatbot,
      name: "Chain of Thought",
      summary: "Ordered reasoning steps from a data part",
      variants: [
        .init(id: "chain-of-thought/basic", title: "Basic", description: "Rendered via assistantMessageDataRenderer") {
          AnyView(ChainOfThoughtDemoView())
        },
      ]
    ),
    .init(
      id: "plan",
      category: .chatbot,
      name: "Plan",
      summary: "Checklist of plan items from a data part",
      variants: [
        .init(id: "plan/basic", title: "Basic", description: "Rendered via assistantMessageDataRenderer") {
          AnyView(PlanDemoView())
        },
      ]
    ),
    .init(
      id: "loader",
      category: .utilities,
      name: "Loader",
      summary: "Loading indicator",
      variants: [
        .init(id: "loader/basic", title: "Basic", description: nil) {
          AnyView(LoaderDemoView())
        },
      ]
    ),
    .init(
      id: "context-usage",
      category: .utilities,
      name: "Context Usage",
      summary: "Compact context-window usage indicator",
      variants: [
        .init(id: "context-usage/basic", title: "Basic", description: "Used / max with progress bar") {
          AnyView(ContextUsageDemoView())
        },
      ]
    ),
    .init(
      id: "generated-image",
      category: .utilities,
      name: "Generated Image",
      summary: "Generated image placeholder + resolved image preview",
      variants: [
        .init(id: "generated-image/states", title: "States", description: "Empty, loading shimmer, success, failure") {
          AnyView(GeneratedImageDemoView())
        },
      ]
    ),
    .init(
      id: "generated-image-grid-item",
      category: .utilities,
      name: "Generated Image Grid Item",
      summary: "Gallery-ready square item for generated images",
      variants: [
        .init(id: "generated-image-grid-item/states", title: "States", description: "Compact loading + success") {
          AnyView(GeneratedImageGridItemDemoView())
        },
      ]
    ),
    .init(
      id: "code-block",
      category: .utilities,
      name: "Code Block",
      summary: "Code presentation + copy affordance",
      variants: [
        .init(id: "code-block/basic", title: "Basic", description: nil) {
          AnyView(CodeBlockDemoView())
        },
      ]
    ),
    .init(
      id: "web-preview",
      category: .vibeCoding,
      name: "Web Preview",
      summary: "Preview URL output (likely WKWebView) + optional console",
      variants: [
        .init(id: "web-preview/basic", title: "Basic", description: nil) {
          AnyView(PlaceholderDemoView(title: "Web Preview", detail: "TODO: implement WebPreview demo"))
        },
      ]
    ),
    .init(
      id: "artifact",
      category: .vibeCoding,
      name: "Artifact",
      summary: "Document/code artifact container",
      variants: [
        .init(id: "artifact/basic", title: "Basic", description: nil) {
          AnyView(PlaceholderDemoView(title: "Artifact", detail: "TODO: implement Artifact demo"))
        },
      ]
    ),
    .init(
      id: "canvas",
      category: .workflow,
      name: "Canvas",
      summary: "Workflow graph canvas",
      variants: [
        .init(id: "canvas/basic", title: "Basic", description: nil) {
          AnyView(PlaceholderDemoView(title: "Canvas", detail: "TODO: implement workflow canvas demo"))
        },
      ]
    ),
  ]
}
