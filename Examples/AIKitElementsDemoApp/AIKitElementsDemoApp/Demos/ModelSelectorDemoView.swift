import SwiftUI
import AIKitElements

struct ModelSelectorDemoView: View {
  @State private var selection = "gpt-5"

  private let options: [ModelOption] = [
    .init(id: "gpt-5", name: "GPT-5"),
    .init(id: "claude-opus", name: "Claude Opus"),
    .init(id: "gemini-pro", name: "Gemini Pro"),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ModelSelector(options: options, selection: $selection)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
