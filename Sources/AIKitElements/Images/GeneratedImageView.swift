import SwiftUI
import AIKit
import Shimmer

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum GeneratedImagePhase: Sendable, Equatable {
  case empty
  case loading
  case success(GeneratedFile)
  case failure(String)
}

public struct GeneratedImageView: View {
  public var phase: GeneratedImagePhase
  public var cornerRadius: CGFloat
  public var aspectRatio: CGFloat
  public var contentMode: ContentMode
  public var padding: CGFloat
  public var loadingShimmer: Bool

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    phase: GeneratedImagePhase,
    cornerRadius: CGFloat = 20,
    aspectRatio: CGFloat = 1,
    contentMode: ContentMode = .fill,
    padding: CGFloat = 4,
    loadingShimmer: Bool = true
  ) {
    self.phase = phase
    self.cornerRadius = cornerRadius
    self.aspectRatio = aspectRatio
    self.contentMode = contentMode
    self.padding = padding
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
            .padding(padding)
            .accessibilityLabel("Generated image")
        } else {
          minimalistStatus(
            title: "Image unavailable",
            systemImage: "photo",
            message: "The image data couldn’t be decoded."
          )
        }

      case .loading:
        generatingStatus
          .padding(20)

      case .failure(let message):
        minimalistStatus(
          title: "Couldn’t generate image",
          systemImage: "exclamationmark.triangle",
          message: message
        )

      case .empty:
        minimalistStatus(
          title: "Your image appears here",
          systemImage: "photo",
          message: "Write a prompt and generate."
        )
      }
    }
    .clipShape(shape)
    .aspectRatio(aspectRatio, contentMode: .fit)
  }

  @ViewBuilder
  private var generatingStatus: some View {
    let text = "Generating image..."

    if reduceMotion || loadingShimmer == false {
      Text(text)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityLabel(text)
    } else {
      ZStack(alignment: .leading) {
        Text(text)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)

        Text(text)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(shimmerHighlightColor)
          .shimmering(bandSize: 0.70)
          .accessibilityHidden(true)
      }
      .accessibilityLabel(text)
    }
  }

  @ViewBuilder
  private func minimalistStatus(title: String, systemImage: String, message: String?) -> some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(.secondary)

      Text(title)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)

      if let message, message.isEmpty == false {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary.opacity(0.85))
          .multilineTextAlignment(.center)
      }
    }
    .padding(20)
    .frame(maxWidth: 260)
    .accessibilityElement(children: .combine)
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
