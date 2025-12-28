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

private struct AssistantMessageShowsReasoningKey: EnvironmentKey {
  static var defaultValue: Bool = true
}

private struct AssistantMessageToolRenderersKey: EnvironmentKey {
  static var defaultValue: [String: ToolRenderer] = [:]
}

private struct AssistantMessageOnToolApprovalResponseKey: EnvironmentKey {
  static var defaultValue: (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void = { _, _, _ in }
}

private extension EnvironmentValues {
  var assistantMessageShowsReasoning: Bool {
    get { self[AssistantMessageShowsReasoningKey.self] }
    set { self[AssistantMessageShowsReasoningKey.self] = newValue }
  }

  var assistantMessageToolRenderers: [String: ToolRenderer] {
    get { self[AssistantMessageToolRenderersKey.self] }
    set { self[AssistantMessageToolRenderersKey.self] = newValue }
  }

  var assistantMessageOnToolApprovalResponse: (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void {
    get { self[AssistantMessageOnToolApprovalResponseKey.self] }
    set { self[AssistantMessageOnToolApprovalResponseKey.self] = newValue }
  }
}

public extension View {
  func assistantMessageShowsReasoning(_ showsReasoning: Bool) -> some View {
    environment(\.assistantMessageShowsReasoning, showsReasoning)
  }

  func assistantMessageToolRenderers(_ toolRenderers: [String: ToolRenderer]) -> some View {
    environment(\.assistantMessageToolRenderers, toolRenderers)
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

/// Renders a single assistant `ChatMessage` body from `message.parts` (text, reasoning, tools, sources, files).
///
/// This is the primary home for “interleaved part rendering” complexity (especially tools + approvals).
public struct AssistantMessage<AssistantText: View>: View {
  public var parts: [ChatMessagePart]
  public var showsReasoning: Bool?
  public var toolRenderers: [String: ToolRenderer]?
  public var onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)?
  @ViewBuilder public var assistantText: (String) -> AssistantText
  public var assistantReasoningText: ReasoningTextRenderer?

  @Environment(\.assistantMessageShowsReasoning) private var environmentShowsReasoning
  @Environment(\.assistantMessageToolRenderers) private var environmentToolRenderers
  @Environment(\.assistantMessageOnToolApprovalResponse) private var environmentOnToolApprovalResponse

  public init(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    assistantReasoningText: ReasoningTextRenderer? = nil,
    @ViewBuilder assistantText: @escaping (String) -> AssistantText
  ) {
    self.parts = parts
    self.showsReasoning = showsReasoning
    self.toolRenderers = toolRenderers
    self.onToolApprovalResponse = onToolApprovalResponse
    self.assistantReasoningText = assistantReasoningText
    self.assistantText = assistantText
  }

  public init<AssistantReasoningText: View>(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    @ViewBuilder assistantReasoningText: @escaping (String) -> AssistantReasoningText,
    @ViewBuilder assistantText: @escaping (String) -> AssistantText
  ) {
    let renderer: ReasoningTextRenderer = { text in AnyView(assistantReasoningText(text)) }
    self.init(
      parts: parts,
      showsReasoning: showsReasoning,
      toolRenderers: toolRenderers,
      onToolApprovalResponse: onToolApprovalResponse,
      assistantReasoningText: Optional(renderer),
      assistantText: assistantText
    )
  }

  public init(
    parts: [ChatMessagePart],
    showsReasoning: Bool? = nil,
    toolRenderers: [String: ToolRenderer]? = nil,
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    assistantReasoningText: ReasoningTextRenderer? = nil
  ) where AssistantText == Text {
    self.init(
      parts: parts,
      showsReasoning: showsReasoning,
      toolRenderers: toolRenderers,
      onToolApprovalResponse: onToolApprovalResponse,
      assistantReasoningText: assistantReasoningText,
      assistantText: { Text($0) }
    )
  }

  public var body: some View {
    let resolvedShowsReasoning = showsReasoning ?? environmentShowsReasoning
    let resolvedToolRenderers = toolRenderers ?? environmentToolRenderers
    let resolvedOnToolApprovalResponse = onToolApprovalResponse ?? environmentOnToolApprovalResponse

    VStack(alignment: .leading, spacing: 14) {
      ForEach(groupedParts(parts)) { part in
        switch part.kind {
        case .text(let text):
          assistantText(text)
            .frame(maxWidth: .infinity, alignment: .leading)

        case .reasoning(let text, let isStreaming):
          if resolvedShowsReasoning {
            ReasoningDisclosure(isStreaming: isStreaming) {
              if let assistantReasoningText {
                assistantReasoningText(text)
              } else {
                AnyView(assistantText(text))
              }
            }
          }

        case .tool(let tool):
          toolView(tool, toolRenderers: resolvedToolRenderers, onToolApprovalResponse: resolvedOnToolApprovalResponse)

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
    onToolApprovalResponse: @escaping (_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void
  ) -> some View {
    let approvalID = toolApprovalID(tool)
    let sendApproval: (Bool, String?) -> Void = { approved, reason in
      guard let approvalID else { return }
      onToolApprovalResponse(approvalID, approved, reason)
    }

    if let renderer = toolRenderers[tool.toolName] {
      renderer(.init(tool: tool, isLoading: toolIsLoading(tool.state), sendApproval: sendApproval))
    } else {
      ToolPartView(tool: tool, sendApproval: sendApproval)
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
        result.append(.init(id: id, kind: .reasoning(reasoning.text, isStreaming: reasoning.state == .streaming)))
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
