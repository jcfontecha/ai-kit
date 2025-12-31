import SwiftUI

struct ChatSecondaryDisclosureGroup<Label: View, Content: View>: View {
  var isExpanded: Binding<Bool>?
  var contentTopPadding: CGFloat = 16

  @ViewBuilder var content: () -> Content
  @ViewBuilder var label: () -> Label

  init(
    isExpanded: Binding<Bool>? = nil,
    contentTopPadding: CGFloat = 16,
    @ViewBuilder content: @escaping () -> Content,
    @ViewBuilder label: @escaping () -> Label
  ) {
    self.isExpanded = isExpanded
    self.contentTopPadding = contentTopPadding
    self.content = content
    self.label = label
  }

  var body: some View {
    Group {
      if let isExpanded {
        DisclosureGroup(isExpanded: isExpanded) {
          disclosureContent
        } label: {
          disclosureLabel
        }
      } else {
        DisclosureGroup {
          disclosureContent
        } label: {
          disclosureLabel
        }
      }
    }
    .tint(.secondary)
  }

  private var disclosureContent: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, contentTopPadding)
  }

  private var disclosureLabel: some View {
    label()
      .font(.body)
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
  }
}

