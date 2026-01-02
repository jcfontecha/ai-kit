import SwiftUI
import AIKit

#if DEBUG
private struct GeneratedImageViewDemo: View {
  enum DemoState: String, CaseIterable, Identifiable {
    case empty
    case loading
    case success
    case failure

    var id: String { rawValue }
  }

  @State private var state: DemoState = .loading

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("State", selection: $state) {
        ForEach(DemoState.allCases) { state in
          Text(state.rawValue.capitalized).tag(state)
        }
      }
      .pickerStyle(.segmented)

      GeneratedImageView(phase: phase)
    }
    .padding(16)
    .frame(width: 420, height: 520, alignment: .topLeading)
  }

  private var phase: GeneratedImagePhase {
    switch state {
    case .empty:
      return .empty
    case .loading:
      return .loading
    case .success:
      return .success(.init(data: Self.base64Data(Self.blackJpegBase64), mediaType: "image/jpeg"))
    case .failure:
      return .failure("The model request timed out.")
    }
  }

  // 1x1 black JPEG (base64)
  private static let blackJpegBase64 =
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="

  private static func base64Data(_ base64: String) -> Data {
    Data(base64Encoded: base64) ?? Data()
  }
}

#Preview("GeneratedImageView Demo") {
  GeneratedImageViewDemo()
    .environment(\.colorScheme, .light)
}
#endif

