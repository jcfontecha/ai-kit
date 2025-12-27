import SwiftUI
import AIKitElements

struct ToolDemoView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ToolCard(
        title: "fetch_weather_data",
        status: "Pending",
        tint: nil,
        bodyText: "{ \"location\": \"San Francisco\", \"units\": \"fahrenheit\" }"
      )
      ToolCard(
        title: "fetch_weather_data",
        status: "Running",
        tint: Color.yellow.opacity(0.10),
        bodyText: "{ \"location\": \"San Francisco\", \"units\": \"fahrenheit\" }"
      )
      ToolCard(
        title: "fetch_weather_data",
        status: "Completed",
        tint: Color.green.opacity(0.10),
        bodyText: "{ \"temperature\": \"68°F\", \"conditions\": \"Sunny\" }"
      )
      ToolCard(
        title: "fetch_weather_data",
        status: "Error",
        tint: Color.red.opacity(0.10),
        bodyText: "Network error"
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct ToolCard: View {
  let title: String
  let status: String
  let tint: Color?
  let bodyText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "wrench.and.screwdriver")
        Text(title).font(.headline)
        Spacer()
        Text(status)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Capsule().fill(Color.secondary.opacity(0.12)))
      }

      Text(bodyText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }
    .padding(12)
    .glassSurface(cornerRadius: 16, interactive: false, tint: tint)
  }
}
