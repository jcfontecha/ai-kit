import SwiftUI
import AIKit
import AIKitElements

struct GeneratedImageGridItemDemoView: View {
  private enum DemoState: String, CaseIterable, Identifiable {
    case empty
    case loading
    case success
    case failure

    var id: String { rawValue }
  }

  @State private var state: DemoState = .loading

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("State", selection: $state) {
        ForEach(DemoState.allCases) { state in
          Text(state.rawValue.capitalized).tag(state)
        }
      }
      .pickerStyle(.segmented)

      LazyVGrid(columns: columns, spacing: 12) {
        ForEach(0..<4, id: \.self) { index in
          GeneratedImageGridItem(
            phase: phase(for: index),
            cornerRadius: 12
          )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func phase(for index: Int) -> GeneratedImagePhase {
    switch state {
    case .empty:
      return .empty
    case .loading:
      return .loading
    case .success:
      return .success(.init(data: Self.base64Data(Self.blackJpegBase64), mediaType: "image/jpeg"))
    case .failure:
      return index.isMultiple(of: 2) ? .failure("Timed out") : .empty
    }
  }

  // 1x1 black JPEG (base64)
  private static let blackJpegBase64 =
    "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABmX/9k="

  private static func base64Data(_ base64: String) -> Data {
    Data(base64Encoded: base64) ?? Data()
  }
}

