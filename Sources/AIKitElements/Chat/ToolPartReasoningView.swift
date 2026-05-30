import SwiftUI
import AIKit

public struct ToolPartReasoningView: View {
  public var tool: ChatToolPart
  public var icon: Image
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings?
  public var contentRenderer: ToolPartContentRenderer?
  public var open: Binding<Bool>?
  public var defaultOpen: Bool
  public var onOpenChange: ((_ open: Bool) -> Void)?
  public var collapsible: Bool

  @Environment(\.chatTheme) private var chatTheme

  @State private var isOpenState: Bool

  public init(
    tool: ChatToolPart,
    icon: Image = Image(systemName: "wrench.and.screwdriver"),
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings? = nil,
    contentRenderer: ToolPartContentRenderer? = nil,
    open: Binding<Bool>? = nil,
    defaultOpen: Bool = false,
    onOpenChange: ((_ open: Bool) -> Void)? = nil,
    collapsible: Bool = true
  ) {
    self.tool = tool
    self.icon = icon
    self.sendApproval = sendApproval
    self.statusStrings = statusStrings
    self.contentRenderer = contentRenderer
    self.open = open
    self.defaultOpen = defaultOpen
    self.onOpenChange = onOpenChange
    self.collapsible = collapsible
    self._isOpenState = State(initialValue: open?.wrappedValue ?? defaultOpen)
  }

  public init<Content: View>(
    tool: ChatToolPart,
    icon: Image = Image(systemName: "wrench.and.screwdriver"),
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings? = nil,
    open: Binding<Bool>? = nil,
    defaultOpen: Bool = false,
    onOpenChange: ((_ open: Bool) -> Void)? = nil,
    collapsible: Bool = true,
    @ViewBuilder content: @escaping (_ context: ToolPartContentContext) -> Content
  ) {
    self.init(
      tool: tool,
      icon: icon,
      sendApproval: sendApproval,
      statusStrings: statusStrings,
      contentRenderer: { context in AnyView(content(context)) },
      open: open,
      defaultOpen: defaultOpen,
      onOpenChange: onOpenChange,
      collapsible: collapsible
    )
  }

  public var body: some View {
    let resolvedStatusStrings = statusStrings ?? chatTheme.tool.defaultStatusStrings

    Group {
      if collapsible {
        DisclosureGroup(isExpanded: isExpandedBinding) {
          content(resolvedStatusStrings: resolvedStatusStrings)
        } label: {
          header(resolvedStatusStrings: resolvedStatusStrings)
        }
      } else {
        VStack(alignment: .leading, spacing: 0) {
          header(resolvedStatusStrings: resolvedStatusStrings)
          content(resolvedStatusStrings: resolvedStatusStrings)
        }
      }
    }
    .tint(.secondary)
  }

  @ViewBuilder
  private func header(resolvedStatusStrings: ToolStatusStrings) -> some View {
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

  @ViewBuilder
  private func content(resolvedStatusStrings: ToolStatusStrings) -> some View {
    if let contentRenderer {
      contentRenderer(.init(tool: tool, sendApproval: sendApproval, statusStrings: resolvedStatusStrings))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    } else {
      ToolPartDefaultContent(tool: tool, sendApproval: sendApproval)
        .padding(.top, 16)
    }
  }

  private var resolvedIsOpen: Bool { open?.wrappedValue ?? isOpenState }
  private var isExpandedBinding: Binding<Bool> {
    Binding(
      get: { resolvedIsOpen },
      set: { setOpen($0) }
    )
  }

  private func setOpen(_ open: Bool) {
    self.open?.wrappedValue = open
    isOpenState = open
    onOpenChange?(open)
  }

  @ViewBuilder
  private func statusLabel(_ resolvedStatusStrings: ToolStatusStrings) -> some View {
    if labelIsLoading {
      ShimmerText(labelText(resolvedStatusStrings))
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

}
