import SwiftUI
import AIKit

public struct ToolPartContentContext {
  public var tool: ChatToolPart
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings

  public init(
    tool: ChatToolPart,
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?,
    statusStrings: ToolStatusStrings
  ) {
    self.tool = tool
    self.sendApproval = sendApproval
    self.statusStrings = statusStrings
  }
}

public typealias ToolPartContentRenderer = (_ context: ToolPartContentContext) -> AnyView

public struct ToolPartView: View {
  public var tool: ChatToolPart
  public var icon: Image
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings?
  public var contentRenderer: ToolPartContentRenderer?
  public var open: Binding<Bool>?
  public var defaultOpen: Bool
  public var onOpenChange: ((_ open: Bool) -> Void)?

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
    onOpenChange: ((_ open: Bool) -> Void)? = nil
  ) {
    self.tool = tool
    self.icon = icon
    self.sendApproval = sendApproval
    self.statusStrings = statusStrings
    self.contentRenderer = contentRenderer
    self.open = open
    self.defaultOpen = defaultOpen
    self.onOpenChange = onOpenChange
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
      onOpenChange: onOpenChange
    )
  }

  public var body: some View {
    let resolvedStatusStrings = statusStrings ?? chatTheme.tool.defaultStatusStrings
    let (_, statusLabel, tint) = toolStatus(tool.state, statusStrings: resolvedStatusStrings)

    DisclosureGroup(isExpanded: isExpandedBinding) {
      if let contentRenderer {
        contentRenderer(.init(tool: tool, sendApproval: sendApproval, statusStrings: resolvedStatusStrings))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 10)
      } else {
        ToolPartDefaultContent(tool: tool, sendApproval: sendApproval)
      }
    } label: {
      HStack(spacing: 10) {
        icon
        Text(statusLabel)
          .font(.subheadline.weight(.medium))
        Spacer()
      }
    }
    .padding(12)
    .glassSurface(cornerRadius: 16, interactive: false, tint: tint)
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
}

struct ToolPartDefaultContent: View {
  let tool: ChatToolPart
  let sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let inputText = toolInputText(tool) {
        ToolSection(title: "Parameters") {
          CodeBlock(inputText)
        }
      }

      if let outputText = toolOutputText(tool) {
        ToolSection(title: outputHeading(tool), isError: outputIsError(tool)) {
          CodeBlock(outputText, isError: outputIsError(tool))
        }
      }

      if case .approvalRequested = tool.state {
        ApprovalBanner(
          state: .requested,
          message: "Approve running “\(tool.title ?? tool.toolName)”?",
          onApprove: { sendApproval?(true, nil) },
          onReject: { sendApproval?(false, nil) }
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 10)
  }
}

private struct ToolSection<Content: View>: View {
  let title: String
  var isError: Bool = false
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isError ? .red : .secondary)
      content()
    }
  }
}

private func outputHeading(_ tool: ChatToolPart) -> String {
  switch tool.state {
  case .outputError:
    return "Error"
  case .outputDenied:
    return "Denied"
  default:
    return "Result"
  }
}

private func outputIsError(_ tool: ChatToolPart) -> Bool {
  switch tool.state {
  case .outputError, .outputDenied:
    return true
  default:
    return false
  }
}

private func toolStatus(_ state: ChatToolPart.State) -> (isLoading: Bool, label: String, tint: Color?) {
  switch state {
  case .inputStreaming:
    return (true, "Pending", nil)
  case .inputAvailable:
    return (true, "Running", nil)
  case .approvalRequested:
    return (false, "Awaiting approval", nil)
  case .approvalResponded(_, let approved, _):
    return (false, approved ? "Approved" : "Rejected", approved ? nil : Color.red.opacity(0.10))
  case .outputDenied:
    return (false, "Denied", Color.red.opacity(0.10))
  case .outputAvailable:
    return (false, "Completed", nil)
  case .outputError:
    return (false, "Error", Color.red.opacity(0.10))
  }
}

private func toolStatus(
  _ state: ChatToolPart.State,
  statusStrings: ToolStatusStrings
) -> (isLoading: Bool, label: String, tint: Color?) {
  switch state {
  case .inputStreaming:
    return (true, statusStrings.loading, nil)
  case .inputAvailable:
    return (true, statusStrings.loading, nil)
  case .approvalRequested:
    return (false, "Awaiting approval", nil)
  case .approvalResponded(_, let approved, _):
    return (false, approved ? "Approved" : "Rejected", approved ? nil : Color.red.opacity(0.10))
  case .outputDenied:
    return (false, statusStrings.error, Color.red.opacity(0.10))
  case .outputAvailable:
    return (false, statusStrings.success, nil)
  case .outputError:
    return (false, statusStrings.error, Color.red.opacity(0.10))
  }
}

private func toolInputText(_ tool: ChatToolPart) -> String? {
  if let input = tool.input {
    return prettyJSON(input)
  }
  if let raw = tool.rawInput {
    return prettyJSON(raw)
  }
  return nil
}

private func toolOutputText(_ tool: ChatToolPart) -> String? {
  switch tool.state {
  case .outputAvailable:
    if let output = tool.output {
      return prettyJSON(output)
    }
    return nil
  case .outputError(let errorText):
    return errorText
  case .outputDenied(_, let reason):
    return reason ?? "Tool execution denied."
  default:
    return nil
  }
}

private func prettyJSON(_ value: JSONValue) -> String {
  let encoder = JSONEncoder()
  if #available(iOS 11.0, macOS 10.13, *) {
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  } else {
    encoder.outputFormatting = [.prettyPrinted]
  }
  if let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) {
    return string
  }
  let compact = JSONEncoder()
  if let data = try? compact.encode(value), let string = String(data: data, encoding: .utf8) {
    return string
  }
  return "<invalid json>"
}
