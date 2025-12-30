import SwiftUI
import Shimmer
import AIKit

public struct ToolPartReasoningView: View {
  public var tool: ChatToolPart
  public var icon: Image
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings?
  public var contentRenderer: ToolPartContentRenderer?

  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.chatTheme) private var chatTheme

  public init(
    tool: ChatToolPart,
    icon: Image = Image(systemName: "wrench.and.screwdriver"),
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings? = nil,
    contentRenderer: ToolPartContentRenderer? = nil
  ) {
    self.tool = tool
    self.icon = icon
    self.sendApproval = sendApproval
    self.statusStrings = statusStrings
    self.contentRenderer = contentRenderer
  }

  public init<Content: View>(
    tool: ChatToolPart,
    icon: Image = Image(systemName: "wrench.and.screwdriver"),
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings? = nil,
    @ViewBuilder content: @escaping (_ context: ToolPartContentContext) -> Content
  ) {
    self.init(
      tool: tool,
      icon: icon,
      sendApproval: sendApproval,
      statusStrings: statusStrings,
      contentRenderer: { context in AnyView(content(context)) }
    )
  }

  public var body: some View {
    let resolvedStatusStrings = statusStrings ?? chatTheme.tool.defaultStatusStrings

    DisclosureGroup {
      if let contentRenderer {
        contentRenderer(.init(tool: tool, sendApproval: sendApproval, statusStrings: resolvedStatusStrings))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 16)
      } else {
        ToolPartDefaultContent(tool: tool, sendApproval: sendApproval)
          .padding(.top, 16)
      }
    } label: {
      HStack(spacing: 8) {
        icon
        statusLabel(resolvedStatusStrings)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.body)
      .foregroundStyle(.secondary)
      .contentShape(Rectangle())
    }
    .tint(.secondary)
  }

  @ViewBuilder
  private func statusLabel(_ resolvedStatusStrings: ToolStatusStrings) -> some View {
    if labelIsLoading {
      ZStack(alignment: .leading) {
        Text(labelText(resolvedStatusStrings))
          .foregroundStyle(.secondary)

        Text(labelText(resolvedStatusStrings))
          .foregroundStyle(shimmerHighlightColor)
          .shimmering()
          .accessibilityHidden(true)
      }
    } else {
      Text(labelText(resolvedStatusStrings))
        .foregroundStyle(labelIsError ? .red : .secondary)
    }
  }

  private func labelText(_ resolvedStatusStrings: ToolStatusStrings) -> String {
    if labelIsError { return resolvedStatusStrings.error }
    if labelIsLoading { return resolvedStatusStrings.loading }
    return resolvedStatusStrings.success
  }

  private var labelIsLoading: Bool {
    switch tool.state {
    case .inputStreaming, .inputAvailable, .approvalRequested:
      return true
    case .approvalResponded(_, let approved, _):
      return approved == false
    case .outputDenied, .outputError:
      return false
    case .outputAvailable:
      return false
    }
  }

  private var labelIsError: Bool {
    switch tool.state {
    case .outputDenied, .outputError:
      return true
    case .approvalResponded(_, let approved, _):
      return approved == false
    default:
      return false
    }
  }

  private var shimmerHighlightColor: Color {
    switch colorScheme {
    case .dark:
      return Color.white.opacity(1.0)
    case .light:
      return Color.black.opacity(0.30)
    @unknown default:
      return Color.white.opacity(0.95)
    }
  }
}
