import SwiftUI
import AIKit
import AIKitElements

struct ConversationPerfDemoView: View {
  @State private var items: [ChatMessage] = DemoContent.performanceMessages

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Performance Scenario")
        .font(.headline)
      Text("36 user/assistant pairs, each assistant message includes 3 tool calls.")
        .font(.subheadline)
        .foregroundStyle(.secondary)

      Conversation(messages: items, status: .ready) { message in
        DemoChatMessageView(message: message)
      }
      .frame(height: 520)

      HStack(spacing: 8) {
        Button("Clear") { items = [] }
        Button("Reset") { items = DemoContent.performanceMessages }
        Button("Baseline") { items = DemoContent.initialMessages }
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
  }
}

#Preview {
  ConversationPerfDemoView()
}
