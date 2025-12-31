import SwiftUI

struct ChatLeadingIconLabel<Icon: View, Title: View>: View {
  var iconSlotWidth: CGFloat = 22
  var spacing: CGFloat = 8

  @ViewBuilder var icon: () -> Icon
  @ViewBuilder var title: () -> Title

  init(
    iconSlotWidth: CGFloat = 22,
    spacing: CGFloat = 8,
    @ViewBuilder icon: @escaping () -> Icon,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.iconSlotWidth = iconSlotWidth
    self.spacing = spacing
    self.icon = icon
    self.title = title
  }

  var body: some View {
    HStack(spacing: spacing) {
      ZStack {
        icon()
      }
      .frame(width: iconSlotWidth, alignment: .center)

      title()

      Spacer(minLength: 0)
    }
  }
}

