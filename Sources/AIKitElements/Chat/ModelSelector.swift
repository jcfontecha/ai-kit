import SwiftUI

/// A selectable model entry for ``ModelSelector``.
public struct ModelOption: Identifiable, Hashable, Sendable {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

/// A compact composer model picker. Shows the current model name with a chevron
/// inside a glass pill, modeled on the composer plus-button styling, and opens a
/// native `Menu` for selection.
public struct ModelSelector: View {
  public var options: [ModelOption]
  @Binding public var selection: String

  public init(options: [ModelOption], selection: Binding<String>) {
    self.options = options
    self._selection = selection
  }

  public var body: some View {
    Menu {
      ForEach(options) { option in
        Button {
          selection = option.id
        } label: {
          if option.id == selection {
            Label(option.name, systemImage: "checkmark")
          } else {
            Text(option.name)
          }
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(currentName)
          .lineLimit(1)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .glassEffect(.clear.interactive(), in: .capsule)
      .contentShape(Capsule())
    }
    .menuStyle(.automatic)
  }

  private var currentName: String {
    options.first(where: { $0.id == selection })?.name ?? selection
  }
}
