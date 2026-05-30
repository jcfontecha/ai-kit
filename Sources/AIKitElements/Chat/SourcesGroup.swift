import SwiftUI

/// A single source entry, matching what ``SourceLinkRow`` / ``SourceDocumentRow`` render.
public enum ChatSource: Identifiable, Equatable {
  case link(id: String, url: String, title: String?)
  case document(id: String, title: String, filename: String?, mediaType: String)

  public var id: String {
    switch self {
    case .link(let id, _, _): id
    case .document(let id, _, _, _): id
    }
  }
}

/// A collapsing "Used N sources" container wrapping ``SourceLinkRow`` / ``SourceDocumentRow``.
/// Built on ``ChatSecondaryDisclosureGroup`` — zero chrome, count shown in the label.
public struct SourcesGroup: View {
  public var sources: [ChatSource]

  public init(sources: [ChatSource]) {
    self.sources = sources
  }

  public var body: some View {
    ChatSecondaryDisclosureGroup {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(sources) { source in
          switch source {
          case .link(_, let url, let title):
            SourceLinkRow(url: url, title: title)
          case .document(_, let title, let filename, let mediaType):
            SourceDocumentRow(title: title, filename: filename, mediaType: mediaType)
          }
        }
      }
    } label: {
      Text("Used \(sources.count) source\(sources.count == 1 ? "" : "s")")
    }
  }
}
