import SwiftUI
import AIKitElements

struct SourcesDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SourcesGroup(sources: [
        .link(id: "s-1", url: "https://example.com/docs/aikit", title: "AIKit docs (example)"),
        .document(id: "s-2", title: "Context.pdf", filename: "Context.pdf", mediaType: "application/pdf"),
      ])
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
