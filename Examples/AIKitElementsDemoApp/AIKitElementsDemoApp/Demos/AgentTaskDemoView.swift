import SwiftUI
import AIKitElements

struct AgentTaskDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      AgentTaskView(
        title: "Refactor auth module",
        steps: [
          .init(text: "Read existing session handling", status: .done),
          .init(text: "Extract token refresh", status: .inProgress),
          .init(text: "Add tests", status: .pending),
        ]
      )

      AgentTaskView(
        title: "Index documentation",
        steps: ["Crawl pages", "Chunk content", "Embed and store"]
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
