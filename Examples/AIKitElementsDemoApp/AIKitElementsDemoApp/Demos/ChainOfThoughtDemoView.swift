import SwiftUI
import AIKit
import AIKitElements

struct ChainOfThoughtDemoView: View {
  private let parts: [ChatMessagePart] = [
    .text(.init(id: "t-1", text: "Let me work through this.", state: .done)),
    .data(.init(
      type: ChainOfThought.dataType,
      data: .array([
        .object(["label": .string("Identify the constraints"), "status": .string("done")]),
        .object(["label": .string("Compare candidate approaches"), "status": .string("done")]),
        .object(["label": .string("Draft the implementation"), "status": .string("inProgress")]),
      ])
    )),
  ]

  var body: some View {
    AssistantMessage(parts: parts)
      .assistantMessageDataRenderer { part in
        ChainOfThought(part: part).map { AnyView($0) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
