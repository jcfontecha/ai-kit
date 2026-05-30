import SwiftUI
import Shimmer

/// A single line of text with a shimmering highlight pass, used for streaming
/// "thinking"/tool-status labels. The base layer reads as `.secondary`; a second
/// layer with a higher-contrast highlight shimmers over it.
public struct ShimmerText: View {
  public var text: String

  @Environment(\.colorScheme) private var colorScheme

  public init(_ text: String) {
    self.text = text
  }

  public var body: some View {
    ZStack(alignment: .leading) {
      Text(text)
        .foregroundStyle(.secondary)

      Text(text)
        .foregroundStyle(highlightColor)
        .shimmering()
        .accessibilityHidden(true)
    }
  }

  private var highlightColor: Color {
    switch colorScheme {
    case .dark:
      return Color.white.opacity(1.0)
    case .light:
      return Color.black.opacity(0.30)
    @unknown default:
      return Color.white.opacity(0.95)
    }
  }
}
