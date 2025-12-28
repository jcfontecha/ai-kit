import SwiftUI
import AIKitElements

struct ReasoningDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Streaming")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ReasoningDisclosure(isStreaming: true) {
          Text("I should call tools to fetch data, then summarize it for the user.")
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Complete")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ReasoningDisclosure(
          isStreaming: false,
          open: .constant(false),
          duration: .constant(7 as Int?)
        ) {
          Text("Reasoning finished; this should now be hidden unless you expand it.")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
