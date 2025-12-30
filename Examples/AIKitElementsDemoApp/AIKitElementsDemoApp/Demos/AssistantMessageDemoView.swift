import SwiftUI
import MarkdownUI

import AIKit
import AIKitElements

struct AssistantMessageDemoView: View {
  @State private var showsReasoning: Bool = true
  @State private var approvalResponses: [String: (approved: Bool, reason: String?)] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Show reasoning", isOn: $showsReasoning)
        .font(.subheadline)

      Text("Default tool renderer + custom tool override")
        .font(.headline)

      AssistantMessage(
        parts: demoParts
      )
      .assistantMessageDefaultToolStatusStrings(.init(
        loading: "Loading",
        success: "Completed",
        error: "Error"
      ))
      .assistantMessageTextRenderer { text in
        Markdown(text)
      }
      .assistantMessageReasoningTextRenderer { text in
        Markdown(text)
          .markdownTextStyle { ForegroundColor(.secondary) }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .assistantMessageShowsReasoning(showsReasoning)
      .assistantMessageToolRenderer("fetch_weather_data") { ctx in
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Image(systemName: "cloud.sun")
            Text("Weather")
              .font(.headline)
            Spacer()
            Text(ctx.isLoading ? "Running" : "Done")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Capsule().fill(Color.secondary.opacity(0.12)))
          }

          if let input = ctx.tool.input {
            Text("Input: \(compactJSON(input))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let output = ctx.tool.output {
            Text("Output: \(compactJSON(output))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(12)
        .glassSurface(cornerRadius: 16, interactive: false, tint: Color.blue.opacity(0.08))
      }
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        approvalResponses[approvalID] = (approved: approved, reason: reason)
      }

      Text("Reasoning-style tool renderer (all tools)")
        .font(.headline)
        .padding(.top, 8)

      AssistantMessage(
        parts: demoParts
      )
      .assistantMessageDefaultToolStatusStrings(.init(
        loading: "Working…",
        success: "Done",
        error: "Failed"
      ))
      .assistantMessageDefaultToolRenderer { context in
        AnyView(
          ToolPartReasoningView(
            tool: context.tool,
            icon: Image(systemName: "sparkles"),
            sendApproval: context.sendApproval,
            statusStrings: context.statusStrings
          )
        )
      }
      .assistantMessageTextRenderer { text in
        Markdown(text)
      }
      .assistantMessageReasoningTextRenderer { text in
        Markdown(text)
          .markdownTextStyle { ForegroundColor(.secondary) }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .assistantMessageShowsReasoning(showsReasoning)
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        approvalResponses[approvalID] = (approved: approved, reason: reason)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var demoParts: [ChatMessagePart] {
    let approvalID = "approval-1"
    let response = approvalResponses[approvalID]

    let approvalState: ChatToolPart.State = {
      if let response {
        return .approvalResponded(approvalID: approvalID, approved: response.approved, reason: response.reason)
      }
      return .approvalRequested(approvalID: approvalID)
    }()

    let approval: ChatToolPart.Approval? = {
      if let response {
        return .init(id: approvalID, approved: response.approved, reason: response.reason)
      }
      return .init(id: approvalID)
    }()

    return [
      .text(.init(
        id: "text-1",
        text: """
        Here’s an assistant message that behaves more like an **agent workflow** by interleaving text and tool parts:

        - Markdown rendering
        - Reasoning disclosure
        - Tool parts (including approval)
        - Sources + attachments (inline with the flow)
        """,
        state: .done
      )),
      .reasoning(.init(
        id: "reasoning-1",
        text: "I should call tools to fetch data, then summarize it for the user.",
        state: .done
      )),
      .text(.init(
        id: "text-2",
        text: "First I’ll search the docs, then I’ll fetch weather data.",
        state: .done
      )),
      .tool(.init(
        toolCallID: "tool-search-1",
        toolName: "search_docs",
        title: "search_docs",
        input: .object([
          "query": .string("How does AIKit tool approvals work?"),
        ]),
        state: .inputAvailable
      )),
      .text(.init(
        id: "text-3",
        text: "Found a relevant page. I’ll cite it as a source:",
        state: .done
      )),
      .sourceURL(.init(
        sourceID: "source-1",
        url: "https://example.com/docs/aikit",
        title: "AIKit docs (example)"
      )),
      .text(.init(
        id: "text-4",
        text: "Now I’ll fetch the weather.",
        state: .done
      )),
      .tool(.init(
        toolCallID: "tool-weather-1",
        toolName: "fetch_weather_data",
        title: "fetch_weather_data",
        input: .object([
          "location": .string("San Francisco"),
          "units": .string("fahrenheit"),
        ]),
        output: .object([
          "temperature": .string("68°F"),
          "conditions": .string("Sunny"),
        ]),
        state: .outputAvailable(preliminary: false)
      )),
      .text(.init(
        id: "text-5",
        text: "I’ll attach the report I used for context:",
        state: .done
      )),
      .file(.init(
        data: .base64("JVBERi0xLjQKJcfs..."),
        filename: "report.pdf",
        mediaType: "application/pdf"
      )),
      .sourceDocument(.init(
        sourceID: "doc-1",
        mediaType: "application/pdf",
        title: "Context.pdf",
        filename: "Context.pdf"
      )),
      .text(.init(
        id: "text-6",
        text: "And an image attachment:",
        state: .done
      )),
      .file(.init(
        data: .base64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"),
        filename: "image.png",
        mediaType: "image/png"
      )),
      .text(.init(
        id: "text-7",
        text: "Next I need approval to run a potentially dangerous tool:",
        state: .done
      )),
      .tool(.init(
        toolCallID: "tool-delete-1",
        toolName: "delete_file",
        title: "delete_file",
        providerExecuted: false,
        dynamic: false,
        input: .object([
          "filePath": .string("/tmp/example.txt"),
          "confirm": .bool(true),
        ]),
        callProviderMetadata: nil,
        approval: approval,
        state: approvalState
      )),
      .text(.init(
        id: "text-8",
        text: "If you approve above, I’ll continue; otherwise I’ll stop or choose a safer alternative.",
        state: .done
      )),
      .tool(.init(
        toolCallID: "tool-bad-1",
        toolName: "bad_tool",
        title: "bad_tool",
        input: nil,
        rawInput: .string("{ not: valid json }"),
        state: .outputError(errorText: "Network error")
      )),
      .text(.init(
        id: "text-9",
        text: "That tool failed, so I’ll fall back to a different approach.",
        state: .done
      )),
      .tool(.init(
        toolCallID: "tool-restricted-1",
        toolName: "restricted_tool",
        title: "restricted_tool",
        approval: .init(id: "approval-2", approved: false, reason: "User rejected"),
        state: .outputDenied(approvalID: "approval-2", reason: "User rejected")
      )),
    ]
  }
}

private func compactJSON(_ value: JSONValue) -> String {
  let encoder = JSONEncoder()
  if #available(iOS 11.0, macOS 10.13, *) {
    encoder.outputFormatting = [.sortedKeys]
  }
  guard let data = try? encoder.encode(value) else { return "<invalid json>" }
  return String(data: data, encoding: .utf8) ?? "<invalid json>"
}
