import SwiftUI

/// A single tappable starter-prompt pill. Capsule styling mirrors ``FileChip``.
public struct Suggestion: View {
  public var text: String
  public var onSelect: (String) -> Void

  public init(_ text: String, onSelect: @escaping (String) -> Void) {
    self.text = text
    self.onSelect = onSelect
  }

  public var body: some View {
    Button {
      onSelect(text)
    } label: {
      Text(text)
        .font(.subheadline)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
          Capsule().fill(Color.secondary.opacity(0.12))
        }
    }
    .buttonStyle(.plain)
  }
}

/// A horizontally scrolling row of starter-prompt pills. The scroll container
/// mirrors the composer's attachments row.
public struct Suggestions: View {
  public var suggestions: [String]
  public var onSelect: (String) -> Void

  public init(_ suggestions: [String], onSelect: @escaping (String) -> Void) {
    self.suggestions = suggestions
    self.onSelect = onSelect
  }

  public var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
          Suggestion(suggestion, onSelect: onSelect)
        }
      }
      .padding(.leading, 2)
      .padding(.trailing, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
