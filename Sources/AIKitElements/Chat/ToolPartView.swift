import SwiftUI
import AIKit

public struct ToolPartView: View {
  public var tool: ChatToolPart
  public var sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)?
  public var statusStrings: ToolStatusStrings?

  public init(
    tool: ChatToolPart,
    sendApproval: ((_ approved: Bool, _ reason: String?) -> Void)? = nil,
    statusStrings: ToolStatusStrings? = nil
  ) {
    self.tool = tool
    self.sendApproval = sendApproval
    self.statusStrings = statusStrings
  }

  public var body: some View {
    let (isLoading, statusLabel, tint) = toolStatus(tool.state, statusStrings: statusStrings)

    DisclosureGroup {
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
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "wrench.and.screwdriver")
        Text(tool.title ?? tool.toolName)
          .font(.subheadline.weight(.medium))
        Spacer()
        Text(isLoading ? "Running" : statusLabel)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(Capsule().fill(Color.secondary.opacity(0.12)))
      }
    }
    .padding(12)
    .glassSurface(cornerRadius: 16, interactive: false, tint: tint)
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

private func toolStatus(_ state: ChatToolPart.State) -> (isLoading: Bool, label: String, tint: Color?) {
  switch state {
  case .inputStreaming:
    return (true, "Pending", nil)
  case .inputAvailable:
    return (true, "Running", Color.yellow.opacity(0.10))
  case .approvalRequested:
    return (false, "Awaiting approval", Color.yellow.opacity(0.10))
  case .approvalResponded(_, let approved, _):
    return (false, approved ? "Approved" : "Rejected", approved ? Color.green.opacity(0.10) : Color.red.opacity(0.10))
  case .outputDenied:
    return (false, "Denied", Color.red.opacity(0.10))
  case .outputAvailable:
    return (false, "Completed", Color.green.opacity(0.10))
  case .outputError:
    return (false, "Error", Color.red.opacity(0.10))
  }
}

private func toolStatus(
  _ state: ChatToolPart.State,
  statusStrings: ToolStatusStrings?
) -> (isLoading: Bool, label: String, tint: Color?) {
  guard let statusStrings else {
    return toolStatus(state)
  }
  switch state {
  case .inputStreaming:
    return (true, statusStrings.loading, nil)
  case .inputAvailable:
    return (true, statusStrings.loading, Color.yellow.opacity(0.10))
  case .approvalRequested:
    return (false, "Awaiting approval", Color.yellow.opacity(0.10))
  case .approvalResponded(_, let approved, _):
    return (false, approved ? "Approved" : "Rejected", approved ? Color.green.opacity(0.10) : Color.red.opacity(0.10))
  case .outputDenied:
    return (false, statusStrings.error, Color.red.opacity(0.10))
  case .outputAvailable:
    return (false, statusStrings.success, Color.green.opacity(0.10))
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
