import SwiftUI
import AIKit

public struct ToolRenderContext {
  public var tool: ChatToolPart
  public var isLoading: Bool
  public var sendApproval: (_ approved: Bool, _ reason: String?) -> Void

  public init(
    tool: ChatToolPart,
    isLoading: Bool,
    sendApproval: @escaping (_ approved: Bool, _ reason: String?) -> Void
  ) {
    self.tool = tool
    self.isLoading = isLoading
    self.sendApproval = sendApproval
  }
}

public typealias ToolRenderer = (_ context: ToolRenderContext) -> AnyView
public typealias ReasoningTextRenderer = (_ text: String) -> AnyView
public typealias ToolDefaultRenderer = (_ context: ToolDefaultRenderContext) -> AnyView

public struct ToolStatusStrings: Hashable, Sendable {
  public var loading: String
  public var success: String
  public var error: String

  public init(loading: String, success: String, error: String) {
    self.loading = loading
    self.success = success
    self.error = error
  }
}

public struct ToolDefaultRenderContext {
  public var tool: ChatToolPart
  public var statusStrings: ToolStatusStrings
  public var sendApproval: (_ approved: Bool, _ reason: String?) -> Void

  public init(
    tool: ChatToolPart,
    statusStrings: ToolStatusStrings,
    sendApproval: @escaping (_ approved: Bool, _ reason: String?) -> Void
  ) {
    self.tool = tool
    self.statusStrings = statusStrings
    self.sendApproval = sendApproval
  }
}

private struct AssistantMessageShowsReasoningKey: EnvironmentKey {
  static let defaultValue: Bool = true
}

private struct ToolRendererStore: @unchecked Sendable {
  var value: [String: ToolRenderer]
}

private struct ToolDefaultRendererStore: @unchecked Sendable {
  var value: ToolDefaultRenderer?
}

private struct ToolApprovalResponseStore: @unchecked Sendable {
  var value: (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void
}

private struct AssistantMessageToolRenderersKey: EnvironmentKey {
  static let defaultValue = ToolRendererStore(value: [:])
}

private struct AssistantMessageToolStatusStringsKey: EnvironmentKey {
  static let defaultValue: [String: ToolStatusStrings] = [:]
}

private struct AssistantMessageDefaultToolRendererKey: EnvironmentKey {
  static let defaultValue = ToolDefaultRendererStore(value: nil)
}

private struct AssistantMessageOnToolApprovalResponseKey: EnvironmentKey {
  static let defaultValue = ToolApprovalResponseStore(value: { _, _, _ in })
}

private extension EnvironmentValues {
  var assistantMessageShowsReasoning: Bool {
    get { self[AssistantMessageShowsReasoningKey.self] }
    set { self[AssistantMessageShowsReasoningKey.self] = newValue }
  }

  var assistantMessageToolRenderers: [String: ToolRenderer] {
    get { self[AssistantMessageToolRenderersKey.self].value }
    set { self[AssistantMessageToolRenderersKey.self] = .init(value: newValue) }
  }

  var assistantMessageToolStatusStrings: [String: ToolStatusStrings] {
    get { self[AssistantMessageToolStatusStringsKey.self] }
    set { self[AssistantMessageToolStatusStringsKey.self] = newValue }
  }

  var assistantMessageDefaultToolRenderer: ToolDefaultRenderer? {
    get { self[AssistantMessageDefaultToolRendererKey.self].value }
    set { self[AssistantMessageDefaultToolRendererKey.self] = .init(value: newValue) }
  }

  var assistantMessageOnToolApprovalResponse: (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void {
    get { self[AssistantMessageOnToolApprovalResponseKey.self].value }
    set { self[AssistantMessageOnToolApprovalResponseKey.self] = .init(value: newValue) }
  }
}

public extension View {
  func assistantMessageShowsReasoning(_ showsReasoning: Bool) -> some View {
    environment(\.assistantMessageShowsReasoning, showsReasoning)
  }

  func assistantMessageToolRenderers(_ toolRenderers: [String: ToolRenderer]) -> some View {
    environment(\.assistantMessageToolRenderers, toolRenderers)
  }

  func assistantMessageToolStatusStrings(_ toolStatusStrings: [String: ToolStatusStrings]) -> some View {
    environment(\.assistantMessageToolStatusStrings, toolStatusStrings)
  }

  func assistantMessageToolStatusStrings(
    _ toolName: String,
    loading: String,
    success: String,
    error: String
  ) -> some View {
    modifier(AssistantMessageToolStatusStringsModifier(
      toolName: toolName,
      statusStrings: .init(loading: loading, success: success, error: error)
    ))
  }

  func assistantMessageDefaultToolRenderer(_ renderer: @escaping ToolDefaultRenderer) -> some View {
    environment(\.assistantMessageDefaultToolRenderer, renderer)
  }

  func assistantMessageToolRenderer(_ toolName: String, renderer: @escaping ToolRenderer) -> some View {
    modifier(AssistantMessageToolRendererModifier(toolName: toolName, renderer: renderer))
  }

  func assistantMessageToolRenderer<ToolView: View>(
    _ toolName: String,
    @ViewBuilder renderer: @escaping (_ context: ToolRenderContext) -> ToolView
  ) -> some View {
    assistantMessageToolRenderer(toolName) { context in
      AnyView(renderer(context))
    }
  }

  func assistantMessageOnToolApprovalResponse(
    _ onToolApprovalResponse: @escaping (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void
  ) -> some View {
    environment(\.assistantMessageOnToolApprovalResponse, onToolApprovalResponse)
  }
}

private struct AssistantMessageToolRendererModifier: ViewModifier {
  let toolName: String
  let renderer: ToolRenderer

  @Environment(\.assistantMessageToolRenderers) private var baseToolRenderers

  func body(content: Content) -> some View {
    content.environment(
      \.assistantMessageToolRenderers,
      baseToolRenderers.merging([toolName: renderer], uniquingKeysWith: { _, new in new })
    )
  }
}

private struct AssistantMessageToolStatusStringsModifier: ViewModifier {
  let toolName: String
  let statusStrings: ToolStatusStrings

  @Environment(\.assistantMessageToolStatusStrings) private var baseToolStatusStrings

  func body(content: Content) -> some View {
    content.environment(
      \.assistantMessageToolStatusStrings,
      baseToolStatusStrings.merging([toolName: statusStrings], uniquingKeysWith: { _, new in new })
    )
  }
}

/// Renders a single assistant `ChatMessage` body from `message.parts` (text, reasoning, tools, sources, files).
///
/// This is the primary home for “interleaved part rendering” complexity (especially tools + approvals).
public struct AssistantMessage<AssistantText: View>: View {
  public var parts: [ChatMessagePart]
  public var showsReasoning: Bool?
  public var toolRenderers: [String: ToolRenderer]?
  public var toolStatusStrings: [String: ToolStatusStrings]?
  public var toolDefaultStatusStrings: ToolStatusStrings
  public var toolDefaultRenderer: ToolDefaultRenderer?
  public var onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)?
  @ViewBuilder public var assistantText: (String) -> AssistantText
  public var assistantReasoningText: ReasoningTextRenderer?

  @Environment(\.assistantMessageShowsReasoning) private var environmentShowsReasoning
  @Environment(\.assistantMessageToolRenderers) private var environmentToolRenderers
  @Environment(\.assistantMessageToolStatusStrings) private var environmentToolStatusStrings
  @Environment(\.assistantMessageDefaultToolRenderer) private var environmentDefaultToolRenderer
  @Environment(\.assistantMessageOnToolApprovalResponse) private var environmentOnToolApprovalResponse

  public init(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    toolStatusStrings: [String: ToolStatusStrings]? = nil,
    toolDefaultStatusStrings: ToolStatusStrings,
    toolDefaultRenderer: ToolDefaultRenderer? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    assistantReasoningText: ReasoningTextRenderer? = nil,
    @ViewBuilder assistantText: @escaping (String) -> AssistantText
  ) {
    self.parts = parts
    self.showsReasoning = showsReasoning
    self.toolRenderers = toolRenderers
    self.toolStatusStrings = toolStatusStrings
    self.toolDefaultStatusStrings = toolDefaultStatusStrings
    self.toolDefaultRenderer = toolDefaultRenderer
    self.onToolApprovalResponse = onToolApprovalResponse
    self.assistantReasoningText = assistantReasoningText
    self.assistantText = assistantText
  }

  public init<AssistantReasoningText: View>(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    toolStatusStrings: [String: ToolStatusStrings]? = nil,
    toolDefaultStatusStrings: ToolStatusStrings,
    toolDefaultRenderer: ToolDefaultRenderer? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    @ViewBuilder assistantReasoningText: @escaping (String) -> AssistantReasoningText,
    @ViewBuilder assistantText: @escaping (String) -> AssistantText
  ) {
    let renderer: ReasoningTextRenderer = { text in AnyView(assistantReasoningText(text)) }
    self.init(
      parts: parts,
      showsReasoning: showsReasoning,
      toolRenderers: toolRenderers,
      toolStatusStrings: toolStatusStrings,
      toolDefaultStatusStrings: toolDefaultStatusStrings,
      toolDefaultRenderer: toolDefaultRenderer,
      onToolApprovalResponse: onToolApprovalResponse,
      assistantReasoningText: Optional(renderer),
      assistantText: assistantText
    )
  }

  public init(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    toolStatusStrings: [String: ToolStatusStrings]? = nil,
    toolDefaultStatusStrings: ToolStatusStrings,
    toolDefaultRenderer: ToolDefaultRenderer? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    assistantReasoningText: ReasoningTextRenderer? = nil
  ) where AssistantText == Text {
    self.init(
      parts: parts,
      showsReasoning: showsReasoning,
      toolRenderers: toolRenderers,
      toolStatusStrings: toolStatusStrings,
      toolDefaultStatusStrings: toolDefaultStatusStrings,
      toolDefaultRenderer: toolDefaultRenderer,
      onToolApprovalResponse: onToolApprovalResponse,
      assistantReasoningText: assistantReasoningText,
      assistantText: { Text($0) }
    )
  }

  public var body: some View {
    let resolvedShowsReasoning = showsReasoning ?? environmentShowsReasoning
    let resolvedToolRenderers = toolRenderers ?? environmentToolRenderers
    let resolvedToolStatusStrings = toolStatusStrings ?? environmentToolStatusStrings
    let resolvedToolDefaultStatusStrings = toolDefaultStatusStrings
    let resolvedToolDefaultRenderer = toolDefaultRenderer ?? environmentDefaultToolRenderer
    let resolvedOnToolApprovalResponse = onToolApprovalResponse ?? environmentOnToolApprovalResponse

    VStack(alignment: .leading, spacing: 14) {
      ForEach(groupedParts(parts)) { part in
        switch part.kind {
        case .text(let text):
          assistantText(text)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .reasoning(let text, let isStreaming):
          if resolvedShowsReasoning {
            ReasoningDisclosure(isStreaming: isStreaming, defaultOpen: false) {
              if let assistantReasoningText {
                assistantReasoningText(text)
              } else {
                AnyView(assistantText(text))
              }
            }
          }

        case .tool(let tool):
          toolView(
            tool,
            toolRenderers: resolvedToolRenderers,
            toolStatusStrings: resolvedToolStatusStrings,
            toolDefaultStatusStrings: resolvedToolDefaultStatusStrings,
            toolDefaultRenderer: resolvedToolDefaultRenderer,
            onToolApprovalResponse: resolvedOnToolApprovalResponse
          )

        case .fileGroup(let attachments):
          FileAttachmentsRow(attachments: attachments)

        case .sourceURL(let url, let title):
          SourceLinkRow(url: url, title: title)

        case .sourceDocument(let title, let filename, let mediaType):
          SourceDocumentRow(title: title, filename: filename, mediaType: mediaType)

        case .stepStart, .data:
          EmptyView()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func toolView(
    _ tool: ChatToolPart,
    toolRenderers: [String: ToolRenderer],
    toolStatusStrings: [String: ToolStatusStrings],
    toolDefaultStatusStrings: ToolStatusStrings,
    toolDefaultRenderer: ToolDefaultRenderer?,
    onToolApprovalResponse: @escaping (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void
  ) -> some View {
    let approvalID = toolApprovalID(tool)
    let sendApproval: (Bool, String?) -> Void = { approved, reason in
      guard let approvalID else { return }
      onToolApprovalResponse(approvalID, approved, reason)
    }

    if let renderer = toolRenderers[tool.toolName] {
      renderer(.init(tool: tool, isLoading: toolIsLoading(tool.state), sendApproval: sendApproval))
    } else if let toolDefaultRenderer {
      toolDefaultRenderer(.init(
        tool: tool,
        statusStrings: toolStatusStrings[tool.toolName] ?? toolDefaultStatusStrings,
        sendApproval: sendApproval
      ))
    } else {
      let statusStrings = toolStatusStrings[tool.toolName] ?? toolDefaultStatusStrings
      ToolPartView(tool: tool, sendApproval: sendApproval, statusStrings: statusStrings)
    }
  }
}

private struct GroupedPart: Identifiable {
  enum Kind {
    case stepStart
    case text(String)
    case reasoning(String, isStreaming: Bool)
    case fileGroup([FileAttachment])
    case sourceURL(url: String, title: String?)
    case sourceDocument(title: String, filename: String?, mediaType: String)
    case tool(ChatToolPart)
    case data(type: String, id: String?, value: JSONValue)
  }

  var id: String
  var kind: Kind
}

private func groupedParts(_ parts: [ChatMessagePart]) -> [GroupedPart] {
  var result: [GroupedPart] = []
  var fileBuffer: [FileAttachment] = []
  var fileGroupIndex = 0

  func flushFiles() {
    guard fileBuffer.isEmpty == false else { return }
    result.append(.init(id: "files-\(fileGroupIndex)", kind: .fileGroup(fileBuffer)))
    fileGroupIndex += 1
    fileBuffer.removeAll(keepingCapacity: true)
  }

    for (idx, part) in parts.enumerated() {
      switch part {
    case .file(let file):
      fileBuffer.append(.init(id: "file-\(idx)", filename: file.filename, mediaType: file.mediaType))

    default:
      flushFiles()
      let id = "part-\(idx)"
      switch part {
      case .stepStart:
        result.append(.init(id: id, kind: .stepStart))
      case .text(let text):
        result.append(.init(id: id, kind: .text(text.text)))
      case .reasoning(let reasoning):
        let hasLaterNonReasoning = parts[(idx + 1)...].contains { nextPart in
          switch nextPart {
          case .reasoning, .stepStart, .data, .file:
            return false
          default:
            return true
          }
        }
        let isStreaming = reasoning.state == .streaming && hasLaterNonReasoning == false
        result.append(.init(id: id, kind: .reasoning(reasoning.text, isStreaming: isStreaming)))
      case .sourceURL(let source):
        result.append(.init(id: id, kind: .sourceURL(url: source.url, title: source.title)))
      case .sourceDocument(let doc):
        result.append(.init(id: id, kind: .sourceDocument(title: doc.title, filename: doc.filename, mediaType: doc.mediaType)))
      case .tool(let tool):
        result.append(.init(id: id, kind: .tool(tool)))
      case .data(let data):
        result.append(.init(id: id, kind: .data(type: data.type, id: data.id, value: data.data)))
      case .file:
        break
      }
    }
  }
  flushFiles()
  return result
}

private func toolApprovalID(_ tool: ChatToolPart) -> String? {
  if let approval = tool.approval {
    return approval.id
  }
  switch tool.state {
  case .approvalRequested(let approvalID):
    return approvalID
  case .approvalResponded(let approvalID, _, _):
    return approvalID
  case .outputDenied(let approvalID, _):
    return approvalID
  default:
    return nil
  }
}

private func toolIsLoading(_ state: ChatToolPart.State) -> Bool {
  switch state {
  case .inputStreaming, .inputAvailable:
    return true
  case .approvalRequested, .approvalResponded, .outputDenied, .outputAvailable, .outputError:
    return false
  }
}
