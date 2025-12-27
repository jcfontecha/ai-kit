import SwiftUI

public struct AIKitGlassSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  public var cornerRadius: CGFloat
  public var tint: Color?

  public init(
    cornerRadius: CGFloat = 20,
    tint: Color? = nil
  ) {
    self.cornerRadius = cornerRadius
    self.tint = tint
  }

  public func body(content: Content) -> some View {
    content
      .background {
        if reduceTransparency {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.aiKitPlatformBackground.opacity(0.95))
        } else if #available(iOS 26.0, macOS 26.0, *) {
          Color.clear
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
            .overlay {
              if let tint {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                  .fill(tint)
              }
            }
        } else {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
        }
      }
  }
}

public extension View {
  func aiKitGlassSurface(
    cornerRadius: CGFloat = 20,
    tint: Color? = nil
  ) -> some View {
    modifier(AIKitGlassSurface(cornerRadius: cornerRadius, tint: tint))
  }
}

