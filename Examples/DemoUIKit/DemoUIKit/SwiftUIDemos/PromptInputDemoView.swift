import SwiftUI
import AIKitCore
import AIKitElements

struct PromptInputDemoView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case idle
    case typing
    case streaming

    var id: String { rawValue }
  }

  let mode: Mode
  @State private var text: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("This is a single glass surface (chrome). Message content should stay non-glass.")
        .font(.caption)
        .foregroundStyle(.secondary)

      PromptInput(
        text: $text,
        status: mode == .streaming ? .streaming : .ready,
        onSend: { _ in },
        onStop: { }
      )
      .onAppear {
        switch mode {
        case .idle:
          text = ""
        case .typing:
          text = "Hello from the composer"
        case .streaming:
          text = "Streaming…"
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

