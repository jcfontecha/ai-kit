import SwiftUI

struct LoaderDemoView: View {
  @State private var spinning = true

  var body: some View {
    HStack(spacing: 12) {
      ProgressView()
        .progressViewStyle(.circular)
      Text(spinning ? "Loading…" : "Stopped")
      Spacer()
      Toggle("Spin", isOn: $spinning)
        .labelsHidden()
    }
  }
}

