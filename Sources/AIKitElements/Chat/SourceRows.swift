import SwiftUI

public struct SourceLinkRow: View {
  public var url: String
  public var title: String?

  public init(url: String, title: String?) {
    self.url = url
    self.title = title
  }

  public var body: some View {
    let label = title ?? url
    if let dest = URL(string: url) {
      Link(label, destination: dest)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

public struct SourceDocumentRow: View {
  public var title: String
  public var filename: String?
  public var mediaType: String

  public init(title: String, filename: String?, mediaType: String) {
    self.title = title
    self.filename = filename
    self.mediaType = mediaType
  }

  public var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "doc")
        .font(.caption)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
        Text(filename ?? mediaType)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

