import SwiftUI
import MarkdownUI

import AIKit
import AIKitElements

struct AssistantMessageDemoView: View {
  @State private var showsReasoning: Bool = true
  @State private var groupTools: Bool = true
  @State private var approvalResponses: [String: (approved: Bool, reason: String?)] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Show reasoning", isOn: $showsReasoning)
        .font(.subheadline)

      Text("Grouped tool calls (consecutive same tool)")
        .font(.headline)

      Toggle("Group consecutive tool calls", isOn: $groupTools)
        .font(.subheadline)

      AssistantMessage(
        parts: groupedDemoParts
      )
      .assistantMessageToolStatusStrings(
        "search_exercises",
        loading: "Searching for exercises…",
        success: "Found exercises",
        error: "Search failed"
      )
      .assistantMessageToolGrouping(groupTools ? .sameTool : nil)
      .assistantMessageToolTransition(.opacity.combined(with: .move(edge: .top)))
      .animation(.snappy, value: groupTools)
      .assistantMessageTextRenderer { text in
        Markdown(text)
      }
      .assistantMessageReasoningTextRenderer { text in
        Markdown(text)
          .markdownTextStyle { ForegroundColor(.secondary) }
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .assistantMessageShowsReasoning(showsReasoning)

      Text("Default tool renderer + custom tool override")
        .font(.headline)
        .padding(.top, 8)

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

  private var groupedDemoParts: [ChatMessagePart] {
    func search(_ index: Int, _ query: String) -> ChatMessagePart {
      .tool(.init(
        toolCallID: "exercise-search-\(index)",
        toolName: "search_exercises",
        title: "search_exercises",
        input: .object(["query": .string(query)]),
        output: .object(["matches": .number(Double(3 + index % 4))]),
        state: .outputAvailable(preliminary: false)
      ))
    }

    var parts: [ChatMessagePart] = [
      .text(.init(
        id: "grouped-text-1",
        text: "Building a **full-body superset routine**. Let me find exercises for each muscle group.",
        state: .done
      )),
    ]

    let firstBatch = ["chest press", "incline press", "chest fly", "push-up", "dip", "cable crossover", "squat", "leg press"]
    for (offset, query) in firstBatch.enumerated() {
      parts.append(search(offset, query))
    }

    parts.append(.reasoning(.init(
      id: "grouped-reasoning-1",
      text: "I have the push movements. Now I’ll pull from the back and arm catalog.",
      state: .done
    )))

    let secondBatch = ["lat pulldown", "barbell row", "face pull", "bicep curl", "hammer curl"]
    for (offset, query) in secondBatch.enumerated() {
      parts.append(search(firstBatch.count + offset, query))
    }

    parts.append(.tool(.init(
      toolCallID: "create-routine-1",
      toolName: "create_routine",
      title: "create_routine",
      input: .object(["name": .string("Full Body Superset")]),
      output: .object(["exercises": .number(7)]),
      state: .outputAvailable(preliminary: false)
    )))

    parts.append(.text(.init(
      id: "grouped-text-2",
      text: "Done — your **Full Body Superset** routine is ready with 7 exercises.",
      state: .done
    )))

    return parts
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
