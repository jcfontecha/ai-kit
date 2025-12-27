import SwiftUI

struct GlassSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var cornerRadius: CGFloat
  var interactive: Bool
  var tint: Color?

  func body(content: Content) -> some View {
    content
      .background {
        if reduceTransparency {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.platformBackground.opacity(0.95))
        } else if #available(iOS 26.0, macOS 26.0, *) {
          Color.clear
            .glassEffect()
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

extension View {
  func glassSurface(
    cornerRadius: CGFloat = 20,
    interactive: Bool = false,
    tint: Color? = nil
  ) -> some View {
    modifier(GlassSurface(cornerRadius: cornerRadius, interactive: interactive, tint: tint))
  }
}
