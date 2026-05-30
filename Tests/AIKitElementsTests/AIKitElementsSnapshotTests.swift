import XCTest
import SwiftUI

import AIKit
import AIKitProviders
import AIKitElements
import AIKitTestKit

@MainActor
final class AIKitElementsSnapshotTests: XCTestCase {
  // 1x1 black JPEG (base64)
  private static let blackJpegBase64 =
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="

  private static func base64Data(_ base64: String) -> Data {
    Data(base64Encoded: base64) ?? Data()
  }

  func testSnapshot_promptInput_ready() {
    let size = CGSize(width: 420, height: 140)

    let view = snapshotRoot(
      PromptInput(
        text: .constant("Hello from snapshots"),
        status: .ready,
        onSend: { _ in },
        onStop: {}
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_promptInput_ready_longTextWraps() {
    let size = CGSize(width: 360, height: 220)

    let view = snapshotRoot(
      PromptInput(
        text: .constant("This is a long message that should wrap onto multiple lines as you keep typing, without needing to insert explicit newline characters."),
        status: .ready,
        onSend: { _ in },
        onStop: {}
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_promptInput_ready_hidesUnavailableAddButtonViaTheme() {
    let size = CGSize(width: 420, height: 140)

    let view = snapshotRoot(
      PromptInput(
        text: .constant("Hello from snapshots"),
        status: .ready,
        onSend: { _ in },
        onStop: {}
      )
      .chatTheme(
        .init(
          composer: .init(
            addButton: .init(unavailableVisibility: .hidden)
          )
        )
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_promptInput_ready_withThemeOverrides() {
    let size = CGSize(width: 420, height: 140)

    let view = snapshotRoot(
      PromptInput(
        text: .constant("Hello from snapshots"),
        status: .ready,
        onSend: { _ in },
        onStop: {}
      )
      .chatTheme(
        .init(
          composer: .init(
            sendButton: .init(
              foreground: .black,
              background: .orange
            )
          )
        )
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_assistantMessage_interleavedParts() {
    let size = CGSize(width: 480, height: 680)

    let parts: [ChatMessagePart] = [
      .text(.init(
        id: "t-1",
        text: "Here’s a message with **Markdown**, reasoning, tools, and sources.",
        state: .done
      )),
      .reasoning(.init(
        id: "r-1",
        text: "I should call the tool, then explain the result.",
        state: .done
      )),
      .tool(.init(
        toolCallID: "call-1",
        toolName: "fetch_weather",
        title: "Weather",
        input: .object(["city": .string("San Francisco"), "unit": .string("c")]),
        output: .object(["temp": .number(18), "condition": .string("Cloudy")]),
        approval: .init(id: "approval-1", approved: true),
        state: .outputAvailable(preliminary: false)
      )),
      .sourceURL(.init(sourceID: "s-1", url: "https://example.com", title: "Example Source")),
      .sourceDocument(.init(
        sourceID: "doc-1",
        mediaType: "application/pdf",
        title: "Spec PDF",
        filename: "spec.pdf"
      )),
    ]

    let view = snapshotRoot(
      VStack(alignment: .leading, spacing: 16) {
        AssistantMessage(messageID: "m-1", parts: parts)
          .assistantMessageToolRenderer("fetch_weather") { ctx in
            ToolPartReasoningView(
              tool: ctx.tool,
              icon: Image(systemName: "cloud.sun"),
              sendApproval: ctx.sendApproval,
              statusStrings: .init(loading: "Fetching…", success: "Done", error: "Failed")
            )
          }
      },
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_conversation_withComposer() {
    let size = CGSize(width: 520, height: 900)

    let messages: [ChatMessage] = [
      .init(
        id: "u-1",
        role: .user,
        parts: [
          .text(.init(id: "ut-1", text: "Show me something cool.", state: .done))
        ]
      ),
      .init(
        id: "a-1",
        role: .assistant,
        parts: [
          .text(.init(
            id: "at-1",
            text: "Sure — here’s a small demo conversation.",
            state: .done
          )),
          .tool(.init(
            toolCallID: "call-2",
            toolName: "sleep_ms",
            title: "Sleep",
            input: .object(["ms": .number(250)]),
            approval: .init(id: "approval-2"),
            state: .approvalRequested(approvalID: "approval-2")
          )),
        ]
      ),
    ]

    let view = snapshotRoot(
      Conversation(messages: messages, status: .ready)
        .assistantMessageToolRenderer("sleep_ms") { ctx in
          ToolPartReasoningView(
            tool: ctx.tool,
            icon: Image(systemName: "timer"),
            sendApproval: ctx.sendApproval,
            statusStrings: .init(loading: "Sleeping…", success: "Slept", error: "Sleep failed")
          )
        }
        .chatComposer(
          text: .constant("Type here…"),
          status: .ready,
          onSend: { _ in },
          onStop: {}
        ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageView_loading() {
    let size = CGSize(width: 420, height: 420)

    let view = snapshotRoot(
      GeneratedImageView(phase: .loading, loadingShimmer: false),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageView_empty() {
    let size = CGSize(width: 420, height: 420)

    let view = snapshotRoot(
      GeneratedImageView(phase: .empty),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageView_success() {
    let size = CGSize(width: 420, height: 420)

    let file = GeneratedFile(data: Self.base64Data(Self.blackJpegBase64), mediaType: "image/jpeg")

    let view = snapshotRoot(
      GeneratedImageView(phase: .success(file)),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageView_failure() {
    let size = CGSize(width: 420, height: 420)

    let view = snapshotRoot(
      GeneratedImageView(phase: .failure("The model request timed out.")),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageGridItem_loading() {
    let size = CGSize(width: 220, height: 220)

    let view = snapshotRoot(
      GeneratedImageGridItem(phase: .loading, loadingShimmer: false),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_generatedImageGridItem_success() {
    let size = CGSize(width: 220, height: 220)

    let file = GeneratedFile(data: Self.base64Data(Self.blackJpegBase64), mediaType: "image/jpeg")

    let view = snapshotRoot(
      GeneratedImageGridItem(phase: .success(file)),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_userBubble_withThemeOverride() {
    let size = CGSize(width: 300, height: 120)

    let view = snapshotRoot(
      UserBubble(text: "Themed user bubble")
        .chatTheme(
          .init(
            message: .init(
              userBubble: .init(background: .mint)
            )
          )
        ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  // MARK: - New AIKitElements components

  func testSnapshot_shimmerText() {
    let size = CGSize(width: 320, height: 60)

    let view = snapshotRoot(
      ShimmerText("Thinking about your request…"),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_confirmation_requested() {
    let size = CGSize(width: 420, height: 200)

    let view = snapshotRoot(
      Confirmation(
        state: .requested,
        title: "Run shell command?",
        message: "rm -rf ./build",
        onApprove: {},
        onReject: {}
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_confirmation_approved() {
    let size = CGSize(width: 420, height: 140)

    let view = snapshotRoot(
      Confirmation(state: .approved, title: "Run shell command?"),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_suggestions_row() {
    let size = CGSize(width: 460, height: 80)

    let view = snapshotRoot(
      Suggestions(
        ["Summarize this", "Write tests", "Explain the bug"],
        onSelect: { _ in }
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_contextUsage() {
    let size = CGSize(width: 240, height: 48)

    let view = snapshotRoot(
      ContextUsage(used: 12_000, max: 128_000),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  // NOTE: `ModelSelector` is a native `Menu`; its menu content does not render in a
  // static `ImageRenderer` snapshot. We snapshot only the collapsed label here, and
  // cover selection/label logic in `AIKitElementsUnitTests`.
  func testSnapshot_modelSelector_collapsedLabel() {
    let size = CGSize(width: 220, height: 60)

    let view = snapshotRoot(
      ModelSelector(
        options: [
          ModelOption(id: "gpt", name: "GPT-5"),
          ModelOption(id: "claude", name: "Claude"),
        ],
        selection: .constant("claude")
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_sourcesGroup() {
    let size = CGSize(width: 460, height: 200)

    let view = snapshotRoot(
      SourcesGroup(sources: [
        .link(id: "s-1", url: "https://example.com/a", title: "Example A"),
        .link(id: "s-2", url: "https://example.com/b", title: nil),
        .document(id: "d-1", title: "Spec", filename: "spec.pdf", mediaType: "application/pdf"),
      ]),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_inlineCitation_token() {
    let size = CGSize(width: 120, height: 60)

    let view = snapshotRoot(
      InlineCitation(number: 3, url: "https://example.com", title: "Example"),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_agentTaskView_withSteps() {
    let size = CGSize(width: 460, height: 200)

    let view = snapshotRoot(
      AgentTaskView(
        title: "Refactor module",
        steps: [
          AgentTaskView.Step(text: "Read files", status: .done),
          AgentTaskView.Step(text: "Apply edits", status: .inProgress),
          AgentTaskView.Step(text: "Run tests", status: .pending),
        ]
      ),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_chainOfThought_steps() {
    let size = CGSize(width: 460, height: 200)

    let view = snapshotRoot(
      ChainOfThought(steps: [
        ChainOfThought.Step(label: "Identify the relevant files", status: .done),
        ChainOfThought.Step(label: "Trace the data flow", status: .inProgress),
        ChainOfThought.Step(label: "Propose a fix", status: .pending),
      ]),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  func testSnapshot_planView_mixedStatuses() {
    let size = CGSize(width: 460, height: 220)

    let view = snapshotRoot(
      PlanView(items: [
        PlanView.Item(title: "Draft the API", status: .done),
        PlanView.Item(title: "Review with team", status: .inProgress),
        PlanView.Item(title: "Ship", status: .pending),
      ]),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  // Snapshot proof that the data-renderer hook routes a `.data` part to a registered
  // renderer (vs. rendering nothing when absent). Complements the closure-invocation
  // unit test in `AIKitElementsUnitTests`.
  func testSnapshot_assistantMessage_dataRenderer_rendersPlan() {
    let size = CGSize(width: 460, height: 220)

    let parts: [ChatMessagePart] = [
      .text(.init(id: "t-1", text: "Here is the plan:", state: .done)),
      .data(.init(
        type: "data-plan",
        id: "d-1",
        data: .array([
          .object(["title": .string("Step one"), "status": .string("done")]),
          .object(["title": .string("Step two"), "status": .string("pending")]),
        ])
      )),
    ]

    let view = snapshotRoot(
      AssistantMessage(messageID: "m-1", parts: parts)
        .assistantMessageDataRenderer { part -> AnyView? in
          PlanView(part: part).map { AnyView($0) }
        },
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }

  // Companion: with NO renderer, the same `.data` part renders nothing (only the text
  // shows), preserving prior behavior.
  func testSnapshot_assistantMessage_dataRenderer_absentRendersNothing() {
    let size = CGSize(width: 460, height: 120)

    let parts: [ChatMessagePart] = [
      .text(.init(id: "t-1", text: "Here is the plan:", state: .done)),
      .data(.init(
        type: "data-plan",
        id: "d-1",
        data: .array([.object(["title": .string("Hidden"), "status": .string("done")])])
      )),
    ]

    let view = snapshotRoot(
      AssistantMessage(messageID: "m-1", parts: parts),
      size: size
    )

    SnapshotTesting.assertSnapshotImage(view, size: size)
  }
}

@MainActor
private func snapshotRoot<V: View>(_ view: V, size: CGSize) -> some View {
  ZStack {
    Color.white
    view
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(16)
  }
  .frame(width: size.width, height: size.height)
  .environment(\.colorScheme, .light)
  .environment(\.layoutDirection, .leftToRight)
  .environment(\.locale, Locale(identifier: "en_US_POSIX"))
  .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
}
