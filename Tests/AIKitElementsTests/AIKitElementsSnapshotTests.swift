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
