import SwiftUI
import AIKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

import ImageIO

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

  @Environment(\.displayScale) private var displayScale
  @State private var thumbnail: CGImage?

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
      if let thumbnail {
        Image(decorative: thumbnail, scale: displayScale)
          .resizable()
          .scaledToFill()
          .clipped()
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
    .task(id: thumbnailCacheKey) {
      await loadThumbnailIfNeeded()
    }
  }

  private var iconName: String {
    if let mediaType = attachment.mediaType, mediaType.hasPrefix("image/") { return "photo" }
    return "paperclip"
  }

  private var shouldAttemptImagePreview: Bool {
    guard let mediaType = attachment.mediaType, mediaType.hasPrefix("image/") else { return false }
    return true
  }

  private var thumbnailMaxPixelSize: Int {
    Int((size * displayScale).rounded(.up))
  }

  private var thumbnailCacheKey: String {
    guard shouldAttemptImagePreview else { return "no-preview" }
    return makeAttachmentThumbnailCacheKey(attachment: attachment, maxPixelSize: thumbnailMaxPixelSize)
  }

  @MainActor
  private func loadThumbnailIfNeeded() async {
    guard shouldAttemptImagePreview else {
      thumbnail = nil
      return
    }

    if let cached = await AttachmentThumbnailCache.shared.get(thumbnailCacheKey) {
      thumbnail = cached
      return
    }

    let maxPixelSize = thumbnailMaxPixelSize
    let key = thumbnailCacheKey
    let created = await Task.detached(priority: .utility) { () -> CGImage? in
      guard let data = attachmentDataForThumbnail(attachment: attachment) else { return nil }
      return makeThumbnailCGImage(from: data, maxPixelSize: maxPixelSize)
    }.value

    if let created {
      await AttachmentThumbnailCache.shared.insert(created, for: key)
    }
    thumbnail = created
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

private func attachmentDataForThumbnail(attachment: ChatFilePart) -> Data? {
  switch attachment.data {
  case .data(let data):
    return data
  case .base64(let base64):
    return Data(base64Encoded: base64)
  case .url(let url):
    guard url.isFileURL else { return nil }
    return try? Data(contentsOf: url)
  }
}

private func makeThumbnailCGImage(from data: Data, maxPixelSize: Int) -> CGImage? {
  guard maxPixelSize > 0 else { return nil }
  let sourceOptions: [CFString: Any] = [
    kCGImageSourceShouldCache: false,
    kCGImageSourceShouldCacheImmediately: false,
  ]
  guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }

  let thumbnailOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
  ]
  return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
}

private actor AttachmentThumbnailCache {
  static let shared = AttachmentThumbnailCache()

  private let cache: NSCache<NSString, CGImageBox> = {
    let cache = NSCache<NSString, CGImageBox>()
    cache.countLimit = 256
    cache.totalCostLimit = 48 * 1024 * 1024
    return cache
  }()

  func get(_ key: String) -> CGImage? {
    cache.object(forKey: key as NSString)?.image
  }

  func insert(_ image: CGImage, for key: String) {
    let cost = image.bytesPerRow * image.height
    cache.setObject(CGImageBox(image), forKey: key as NSString, cost: cost)
  }
}

private final class CGImageBox: NSObject {
  let image: CGImage
  init(_ image: CGImage) { self.image = image }
}

private func makeAttachmentThumbnailCacheKey(attachment: ChatFilePart, maxPixelSize: Int) -> String {
  "\(maxPixelSize)|\(attachmentKeyFragment(attachment: attachment))"
}

private func attachmentKeyFragment(attachment: ChatFilePart) -> String {
  let mediaType = attachment.mediaType ?? "unknown"
  let filename = attachment.filename ?? "nil"
  return "\(mediaType)|\(filename)|\(dataSignature(attachment.data))"
}

private func dataSignature(_ data: DataContent) -> String {
  switch data {
  case .data(let bytes):
    return "d:\(bytes.count):\(dataEdgeSignature(bytes))"
  case .base64(let base64):
    return "b64:\(base64.count):\(stringEdgeSignature(base64))"
  case .url(let url):
    return "u:\(url.absoluteString)"
  }
}

private func dataEdgeSignature(_ data: Data) -> String {
  guard data.isEmpty == false else { return "empty" }
  let prefix = dataUInt64Prefix(data)
  let suffix = dataUInt64Suffix(data)
  return String(format: "%016llx:%016llx", prefix, suffix)
}

private func stringEdgeSignature(_ string: String) -> String {
  guard string.isEmpty == false else { return "empty" }
  let prefix = String(string.prefix(16))
  let suffix = String(string.suffix(16))
  return "\(prefix):\(suffix)"
}

private func dataUInt64Prefix(_ data: Data) -> UInt64 {
  var value: UInt64 = 0
  let count = min(8, data.count)
  for i in 0..<count {
    value |= UInt64(data[data.startIndex.advanced(by: i)]) << (UInt64(i) * 8)
  }
  return value
}

private func dataUInt64Suffix(_ data: Data) -> UInt64 {
  var value: UInt64 = 0
  let count = min(8, data.count)
  for i in 0..<count {
    value |= UInt64(data[data.endIndex.advanced(by: -(count - i))]) << (UInt64(i) * 8)
  }
  return value
}

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
