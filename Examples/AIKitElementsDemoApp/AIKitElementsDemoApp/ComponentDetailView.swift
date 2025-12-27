import SwiftUI

struct ComponentDetailView: View {
  let component: ComponentDefinition

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text(component.name)
            .font(.largeTitle.bold())
          Text(component.summary)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        ForEach(component.variants) { variant in
          VariantCard(title: variant.title, description: variant.description) {
            variant.build()
          }
        }

        Spacer(minLength: 24)
      }
      .padding(16)
    }
  }
}

private struct VariantCard: View {
  let title: String
  let description: String?
  let content: AnyView

  init(title: String, description: String?, @ViewBuilder content: @escaping () -> AnyView) {
    self.title = title
    self.description = description
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        if let description {
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.04))
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
