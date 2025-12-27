import SwiftUI

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

      HStack(alignment: .bottom, spacing: 10) {
        TextField("Message", text: $text, axis: .vertical)
          .textFieldStyle(.plain)
          .lineLimit(1...5)
          .disabled(mode == .streaming)

        HStack(spacing: 8) {
          Button {
          } label: {
            Image(systemName: "paperclip")
              .frame(width: 34, height: 34)
          }
          .buttonStyle(.plain)
          .glassSurface(cornerRadius: 17, interactive: true)

          if mode == .streaming {
            Button {
            } label: {
              Image(systemName: "stop.fill")
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .glassSurface(cornerRadius: 17, interactive: true, tint: Color.red.opacity(0.12))
          } else {
            Button {
            } label: {
              Image(systemName: "arrow.up")
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .glassSurface(cornerRadius: 17, interactive: true)
          }
        }
      }
      .padding(12)
      .glassSurface(cornerRadius: 24, interactive: false)
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

