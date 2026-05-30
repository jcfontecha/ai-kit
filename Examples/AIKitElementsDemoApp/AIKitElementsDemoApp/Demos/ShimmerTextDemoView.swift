import SwiftUI
import AIKitElements

struct ShimmerTextDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ShimmerText("Thinking...")
      ShimmerText("Searching the web...")
      ShimmerText("Generating response...")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
