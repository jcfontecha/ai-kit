import SwiftUI
import AIKit

/// Collapsed representation of a run of consecutive tool calls (e.g. "Found
/// exercises" ×12). Expanding reveals each underlying call rendered through the
/// normal tool dispatch, so host-registered per-tool renderers still apply.
struct ToolGroupPartView: View {
  let tools: [ChatToolPart]
  let statusStrings: ToolStatusStrings
  var icon: Image = Image(systemName: "wrench.and.screwdriver")
  /// Replaces the collapsed header label. When set the view renders flat (no
  /// glass surface) so the host can match its own tool-call rows.
  var header: ToolGroupHeaderRenderer?
  let childView: (ChatToolPart) -> AnyView

  @State private var isExpanded = false

  var body: some View {
    if let header {
      DisclosureGroup(isExpanded: $isExpanded) {
        groupChildren
      } label: {
        header(tools, statusStrings)
      }
    } else {
      defaultBody
    }
  }

  private var defaultBody: some View {
    let status = aggregateStatus()

    return DisclosureGroup(isExpanded: $isExpanded) {
      groupChildren
    } label: {
      HStack(spacing: 10) {
        icon
        Text(status.label)
          .font(.subheadline.weight(.medium))
        CountBadge(count: tools.count)
        Spacer()
      }
    }
    .padding(12)
    .glassSurface(cornerRadius: 16, interactive: false, tint: status.tint)
  }

  private var groupChildren: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
        childView(tool)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 10)
  }

  private func aggregateStatus() -> (label: String, tint: Color?) {
    if tools.contains(where: { isLoading($0.state) }) {
      return (statusStrings.loading, nil)
    }
    if tools.contains(where: { isError($0.state) }) {
      return (statusStrings.error, Color.red.opacity(0.10))
    }
    return (statusStrings.success, nil)
  }

  private func isLoading(_ state: ChatToolPart.State) -> Bool {
    switch state {
    case .inputStreaming, .inputAvailable:
      return true
    default:
      return false
    }
  }

  private func isError(_ state: ChatToolPart.State) -> Bool {
    switch state {
    case .outputError, .outputDenied:
      return true
    default:
      return false
    }
  }
}

private struct CountBadge: View {
  let count: Int

  var body: some View {
    Text("\(count)")
      .font(.caption2.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
  }
}
