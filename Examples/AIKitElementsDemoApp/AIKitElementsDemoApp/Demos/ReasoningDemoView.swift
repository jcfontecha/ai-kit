import SwiftUI
import AIKitElements

struct ReasoningDemoView: View {
  @State private var isStreaming: Bool = true

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle("Streaming", isOn: $isStreaming)
        .font(.subheadline)

      ReasoningDisclosure(isStreaming: isStreaming) {
        Text("I should call tools to fetch data, then summarize it for the user.")
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

