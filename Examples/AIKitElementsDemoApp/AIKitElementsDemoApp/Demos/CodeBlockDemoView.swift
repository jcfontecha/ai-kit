import SwiftUI
import AIKitElements

struct CodeBlockDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CodeBlock("""
      struct Hello: View {
        var body: some View { Text("Hello") }
      }
      """)

      CodeBlock("Network error", isError: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

