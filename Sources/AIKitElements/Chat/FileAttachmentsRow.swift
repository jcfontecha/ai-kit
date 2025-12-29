import SwiftUI
import AIKit

#if canImport(AppKit)
import AppKit
typealias AttachmentPreviewImage = NSImage
#elseif canImport(UIKit)
import UIKit
typealias AttachmentPreviewImage = UIImage
#endif

public struct FileAttachment: Identifiable, Equatable {
  public var id: String
  public var filename: String?
  public var mediaType: String?

  public init(id: String, filename: String?, mediaType: String?) {
    self.id = id
    self.filename = filename
    self.mediaType = mediaType
  }
}

public struct FileAttachmentsRow: View {
  public var attachments: [FileAttachment]

  public init(attachments: [FileAttachment]) {
    self.attachments = attachments
  }

  public var body: some View {
    HStack(spacing: 8) {
      ForEach(attachments) { attachment in
        FileChip(filename: attachment.filename, mediaType: attachment.mediaType)
      }
    }
  }
}

public struct FileAttachmentPreview: View {
  public var attachment: ChatFilePart
  public var size: CGFloat
  public var cornerRadius: CGFloat

  public init(
    attachment: ChatFilePart,
    size: CGFloat = 52,
    cornerRadius: CGFloat = 10
  ) {
    self.attachment = attachment
    self.size = size
    self.cornerRadius = cornerRadius
  }

  public var body: some View {
    ZStack {
      if let image = previewImage {
        Image(platformImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Image(systemName: iconName)
          .font(.system(size: size * 0.3, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .background(Color.secondary.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }

  private var iconName: String {
    if let mediaType = attachment.mediaType, mediaType.hasPrefix("image/") { return "photo" }
    return "paperclip"
  }

  private var previewImage: AttachmentPreviewImage? {
    guard let mediaType = attachment.mediaType, mediaType.hasPrefix("image/") else { return nil }
    switch attachment.data {
    case .data(let data):
      return platformImage(from: data)
    case .base64(let base64):
      guard let data = Data(base64Encoded: base64) else { return nil }
      return platformImage(from: data)
    case .url:
      return nil
    }
  }
}

public struct FileAttachmentPreviewRow: View {
  public var attachments: [ChatFilePart]
  public var size: CGFloat
  public var cornerRadius: CGFloat
  public var alignment: HorizontalAlignment

  public init(
    attachments: [ChatFilePart],
    size: CGFloat = 52,
    cornerRadius: CGFloat = 10,
    alignment: HorizontalAlignment = .leading
  ) {
    self.attachments = attachments
    self.size = size
    self.cornerRadius = cornerRadius
    self.alignment = alignment
  }

  public var body: some View {
    if attachments.count <= 3 {
      HStack(spacing: 8) {
        if alignment == .trailing { Spacer(minLength: 0) }
        ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
          FileAttachmentPreview(attachment: attachment, size: size, cornerRadius: cornerRadius)
        }
        if alignment == .leading { Spacer(minLength: 0) }
      }
      .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          if alignment == .trailing { Spacer(minLength: 0) }
          ForEach(Array(attachments.enumerated()), id: \.offset) { _, attachment in
            FileAttachmentPreview(attachment: attachment, size: size, cornerRadius: cornerRadius)
          }
          if alignment == .leading { Spacer(minLength: 0) }
        }
        .padding(.leading, 2)
        .padding(.trailing, 4)
      }
    }
  }
}

#if canImport(AppKit)
private func platformImage(from data: Data) -> AttachmentPreviewImage? {
  NSImage(data: data)
}
#elseif canImport(UIKit)
private func platformImage(from data: Data) -> AttachmentPreviewImage? {
  UIImage(data: data)
}
#endif

#if canImport(AppKit)
private extension Image {
  init(platformImage: AttachmentPreviewImage) {
    self.init(nsImage: platformImage)
  }
}
#elseif canImport(UIKit)
private extension Image {
  init(platformImage: AttachmentPreviewImage) {
    self.init(uiImage: platformImage)
  }
}
#endif

public struct FileChip: View {
  public var filename: String?
  public var mediaType: String?

  public init(filename: String?, mediaType: String?) {
    self.filename = filename
    self.mediaType = mediaType
  }

  public var body: some View {
    HStack(spacing: 6) {
      Image(systemName: iconName)
        .font(.caption)
      Text(filename ?? defaultLabel)
        .font(.caption)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background {
      Capsule().fill(Color.secondary.opacity(0.12))
    }
  }

  private var iconName: String {
    if let mediaType, mediaType.hasPrefix("image/") { return "photo" }
    return "paperclip"
  }

  private var defaultLabel: String {
    if let mediaType, mediaType.hasPrefix("image/") { return "Image" }
    return "File"
  }
}
