import SwiftUI
import Shimmer

public struct ShimmeringImagePlaceholder: View {
  public var cornerRadius: CGFloat
  public var bandSize: CGFloat
  public var active: Bool

  @Environment(\.colorScheme) private var colorScheme

  public init(cornerRadius: CGFloat = 16, bandSize: CGFloat = 0.75, active: Bool = true) {
    self.cornerRadius = cornerRadius
    self.bandSize = bandSize
    self.active = active
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    ZStack {
      shape
        .fill(.secondary.opacity(0.18))

      shape
        .fill(shimmerHighlightColor)
        .shimmering(active: active, bandSize: bandSize)
        .opacity(0.14)
    }
    .clipShape(shape)
    .accessibilityHidden(true)
  }

  private var shimmerHighlightColor: Color {
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
