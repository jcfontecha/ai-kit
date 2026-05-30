import SwiftUI
import AIKitElements

struct ContextUsageDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ContextUsage(used: 12_000, max: 128_000)
      ContextUsage(used: 96_500, max: 128_000)
      ContextUsage(used: 128_000, max: 128_000)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
