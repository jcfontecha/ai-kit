import SwiftUI
import AIKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct GeneratedImageGridItem: View {
  public var phase: GeneratedImagePhase
  public var cornerRadius: CGFloat
  public var aspectRatio: CGFloat
  public var contentMode: ContentMode
  public var loadingShimmer: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    phase: GeneratedImagePhase,
    cornerRadius: CGFloat = 12,
    aspectRatio: CGFloat = 1,
    contentMode: ContentMode = .fill,
    loadingShimmer: Bool = true
  ) {
    self.phase = phase
    self.cornerRadius = cornerRadius
    self.aspectRatio = aspectRatio
    self.contentMode = contentMode
    self.loadingShimmer = loadingShimmer
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    ZStack {
      shape
        .fill(.secondary.opacity(0.10))

      switch phase {
      case .success(let file):
        if let image = image(from: file.data) {
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .clipped()
            .clipShape(shape)
            .accessibilityLabel("Generated image")
        } else {
          minimalistStatus(icon: "photo", title: "Unavailable")
        }

      case .loading:
        ShimmeringImagePlaceholder(
          cornerRadius: cornerRadius,
          bandSize: 0.75,
          active: loadingShimmer && reduceMotion == false
        )

      case .failure:
        minimalistStatus(icon: "exclamationmark.triangle", title: "Failed")

      case .empty:
        minimalistStatus(icon: "photo", title: "Empty")
      }
    }
    .clipShape(shape)
    .aspectRatio(aspectRatio, contentMode: .fit)
  }

  private func minimalistStatus(icon: String, title: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .padding(8)
    .accessibilityElement(children: .combine)
  }

  private func image(from data: Data) -> Image? {
    #if canImport(UIKit)
    guard let uiImage = UIImage(data: data) else { return nil }
    return Image(uiImage: uiImage)
    #elseif canImport(AppKit)
    guard let nsImage = NSImage(data: data) else { return nil }
    return Image(nsImage: nsImage)
    #else
    return nil
    #endif
  }
}
