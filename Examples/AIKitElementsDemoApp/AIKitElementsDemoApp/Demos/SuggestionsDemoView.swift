import SwiftUI
import AIKitElements

struct SuggestionsDemoView: View {
  @State private var selected: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Suggestions(
        [
          "Summarize this document",
          "Write a haiku",
          "Explain quantum computing",
          "Draft a follow-up email",
        ],
        onSelect: { selected = $0 }
      )

      if let selected {
        Text("Selected: \(selected)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
