import SwiftUI
import AIKit
import AIKitElements

struct PlanDemoView: View {
  private let parts: [ChatMessagePart] = [
    .data(.init(
      type: PlanView.dataType,
      data: .array([
        .object(["title": .string("Set up the project"), "status": .string("done")]),
        .object(["title": .string("Wire the API client"), "status": .string("inProgress")]),
        .object(["title": .string("Add the settings screen"), "status": .string("pending")]),
        .object(["title": .string("Ship to TestFlight"), "status": .string("pending")]),
      ])
    )),
  ]

  var body: some View {
    AssistantMessage(parts: parts)
      .assistantMessageDataRenderer { part in
        PlanView(part: part).map { AnyView($0) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
