import SwiftUI
import Shimmer
import AIKit

public struct ToolPartReasoningView: View {
  public var tool: ChatToolPart
  public var icon: Image
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings
  public var contentRenderer: ToolPartContentRenderer?

  @Environment(\.colorScheme) private var colorScheme

  public init(
    tool: ChatToolPart,
    icon: Image = Image(systemName: "wrench.and.screwdriver"),
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings,
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
    statusStrings: ToolStatusStrings,
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
    DisclosureGroup {
      if let contentRenderer {
        contentRenderer(.init(tool: tool, sendApproval: sendApproval, statusStrings: statusStrings))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 16)
      } else {
        ToolPartDefaultContent(tool: tool, sendApproval: sendApproval)
          .padding(.top, 16)
      }
    } label: {
      HStack(spacing: 8) {
        icon
        statusLabel
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
  private var statusLabel: some View {
    if labelIsLoading {
      ZStack(alignment: .leading) {
        Text(labelText)
          .foregroundStyle(.secondary)

        Text(labelText)
          .foregroundStyle(shimmerHighlightColor)
          .shimmering()
          .accessibilityHidden(true)
      }
    } else {
      Text(labelText)
        .foregroundStyle(labelIsError ? .red : .secondary)
    }
  }

  private var labelText: String {
    if labelIsError { return statusStrings.error }
    if labelIsLoading { return statusStrings.loading }
    return statusStrings.success
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
