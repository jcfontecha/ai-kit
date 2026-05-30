import SwiftUI
import AIKitElements

struct SourcesDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 8) {
          SourceLinkRow(url: "https://example.com/docs/aikit", title: "AIKit docs (example)")
          SourceDocumentRow(title: "Context.pdf", filename: "Context.pdf", mediaType: "application/pdf")
        }
        .padding(.top, 6)
      } label: {
        Text("Sources (2)")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

