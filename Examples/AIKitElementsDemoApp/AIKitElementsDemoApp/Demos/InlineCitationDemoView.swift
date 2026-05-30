import SwiftUI
import AIKitElements

struct InlineCitationDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        Text("The framework ships with zero-chrome chat primitives")
          .font(.callout)
        InlineCitation(number: 1, url: "https://example.com/docs/aikit", title: "AIKit docs (example)")
      }

      HStack(spacing: 6) {
        Text("Data parts ride the existing ChatDataPart type")
          .font(.callout)
        InlineCitation(number: 2, url: "https://example.com/spec")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
