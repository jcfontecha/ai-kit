import SwiftUI

public struct GlassSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  public var cornerRadius: CGFloat
  public var interactive: Bool
  public var tint: Color?

  public init(
    cornerRadius: CGFloat = 20,
    interactive: Bool = false,
    tint: Color? = nil
  ) {
    self.cornerRadius = cornerRadius
    self.interactive = interactive
    self.tint = tint
  }

  public func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(Color.platformBackground.opacity(0.95), in: shape)
    } else if let tint {
      if interactive {
        content.glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: cornerRadius))
      } else {
        content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
      }
    } else {
      if interactive {
        content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
      } else {
        content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
      }
    }
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
  }
}

public extension View {
  func glassSurface(
    cornerRadius: CGFloat = 20,
    interactive: Bool = false,
    tint: Color? = nil
  ) -> some View {
    modifier(GlassSurface(cornerRadius: cornerRadius, interactive: interactive, tint: tint))
  }
}
