import SwiftUI

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

