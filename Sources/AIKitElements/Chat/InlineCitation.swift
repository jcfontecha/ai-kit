import SwiftUI

/// A footnote-style numbered citation token that reveals its source in a popover on tap.
///
/// MVP scope: truly-inline-in-markdown placement (a token spliced into a rendered
/// paragraph) is out of scope — it would require changes to the markdown renderer.
/// This implements the footnote / numbered-row form: a standalone tappable number.
public struct InlineCitation: View {
  public var number: Int
  public var url: String
  public var title: String?

  @State private var isPresented = false

  public init(number: Int, url: String, title: String? = nil) {
    self.number = number
    self.url = url
    self.title = title
  }

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      Text("\(number)")
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
          Capsule().fill(Color.secondary.opacity(0.12))
        }
    }
    .buttonStyle(.plain)
    .popover(isPresented: $isPresented) {
      SourceLinkRow(url: url, title: title)
        .padding(12)
        .frame(maxWidth: 280)
        .presentationCompactAdaptation(.popover)
    }
  }
}
