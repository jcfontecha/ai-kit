import SwiftUI
import AIKit

private let conversationBottomSentinelID = "chat-bottom-sentinel"
private let conversationTopSentinelID = "chat-top-sentinel"
private let conversationMessagePageSize = 60

public struct Conversation<MessageView: View>: View {
  public var messages: [ChatMessage]
  public var status: ChatSessionStatus
  public var bottomOverlayHeight: CGFloat
  public var showsScrollButton: Bool
  public var toolRenderers: [String: ToolRenderer]
  public var toolStatusStrings: [String: ToolStatusStrings]
  public var toolDefaultStatusStrings: ToolStatusStrings
  public var showsReasoning: Bool
  public var markdownStyle: AssistantMarkdownStyle
  public var onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)?
  @ViewBuilder public var messageView: (ChatMessage) -> MessageView

  @State private var visibleCount: Int = conversationMessagePageSize
  @State private var didPerformInitialScroll: Bool = false
  @State private var isAtBottom: Bool = true
  @State private var pendingScrollTask: Task<Void, Never>?
  @State private var scrollPosition: String? = conversationBottomSentinelID

  private let extraBottomPadding: CGFloat = 0
  private let bottomInsetAnimation: Animation = .easeOut(duration: 0.18)
  private let scrollAnimation: Animation = .easeOut(duration: 0.20)
  private let streamingScrollAnimation: Animation = .easeOut(duration: 0.10)
  private let streamingScrollThrottleNanoseconds: UInt64 = 50_000_000

  public init(
    messages: [ChatMessage],
    status: ChatSessionStatus,
    bottomOverlayHeight: CGFloat,
    showsScrollButton: Bool = false,
    toolRenderers: [String: ToolRenderer] = [:],
    toolStatusStrings: [String: ToolStatusStrings] = [:],
    toolDefaultStatusStrings: ToolStatusStrings = .init(loading: "Working…", success: "Done", error: "Error"),
    showsReasoning: Bool = true,
    markdownStyle: AssistantMarkdownStyle = .init(),
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.messages = messages
    self.status = status
    self.bottomOverlayHeight = bottomOverlayHeight
    self.showsScrollButton = showsScrollButton
    self.toolRenderers = toolRenderers
    self.toolStatusStrings = toolStatusStrings
    self.toolDefaultStatusStrings = toolDefaultStatusStrings
    self.showsReasoning = showsReasoning
    self.markdownStyle = markdownStyle
    self.onToolApprovalResponse = onToolApprovalResponse
    self.messageView = messageView
  }

  public init(
    messages: [ChatMessage],
    bottomOverlayHeight: CGFloat,
    showsScrollButton: Bool = false,
    toolRenderers: [String: ToolRenderer] = [:],
    toolStatusStrings: [String: ToolStatusStrings] = [:],
    toolDefaultStatusStrings: ToolStatusStrings = .init(loading: "Working…", success: "Done", error: "Error"),
    showsReasoning: Bool = true,
    markdownStyle: AssistantMarkdownStyle = .init(),
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil,
    @ViewBuilder messageView: @escaping (ChatMessage) -> MessageView
  ) {
    self.init(
      messages: messages,
      status: .ready,
      bottomOverlayHeight: bottomOverlayHeight,
      showsScrollButton: showsScrollButton,
      toolRenderers: toolRenderers,
      toolStatusStrings: toolStatusStrings,
      toolDefaultStatusStrings: toolDefaultStatusStrings,
      showsReasoning: showsReasoning,
      markdownStyle: markdownStyle,
      onToolApprovalResponse: onToolApprovalResponse,
      messageView: messageView
    )
  }

  public init(
    messages: [ChatMessage],
    status: ChatSessionStatus,
    bottomOverlayHeight: CGFloat,
    showsScrollButton: Bool = false,
    toolStatusStrings: [String: ToolStatusStrings] = [:],
    toolDefaultStatusStrings: ToolStatusStrings = .init(loading: "Working…", success: "Done", error: "Error"),
    showsReasoning: Bool = true,
    markdownStyle: AssistantMarkdownStyle = .init(),
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil
  ) where MessageView == AnyView {
    self.init(
      messages: messages,
      status: status,
      bottomOverlayHeight: bottomOverlayHeight,
      showsScrollButton: showsScrollButton,
      toolRenderers: [:],
      toolStatusStrings: toolStatusStrings,
      toolDefaultStatusStrings: toolDefaultStatusStrings,
      showsReasoning: showsReasoning,
      markdownStyle: markdownStyle,
      onToolApprovalResponse: onToolApprovalResponse
    ) { message in
      AnyView(Self.defaultMessageView(
        message: message,
        toolStatusStrings: toolStatusStrings,
        toolDefaultStatusStrings: toolDefaultStatusStrings,
        markdownStyle: markdownStyle
      ))
    }
  }

  public init(
    messages: [ChatMessage],
    bottomOverlayHeight: CGFloat,
    showsScrollButton: Bool = false,
    toolStatusStrings: [String: ToolStatusStrings] = [:],
    toolDefaultStatusStrings: ToolStatusStrings = .init(loading: "Working…", success: "Done", error: "Error"),
    showsReasoning: Bool = true,
    markdownStyle: AssistantMarkdownStyle = .init(),
    onToolApprovalResponse: ((_ approvalID: String, _ approved: Bool, _ reason: String?) -> Void)? = nil
  ) where MessageView == AnyView {
    self.init(
      messages: messages,
      status: .ready,
      bottomOverlayHeight: bottomOverlayHeight,
      showsScrollButton: showsScrollButton,
      toolStatusStrings: toolStatusStrings,
      toolDefaultStatusStrings: toolDefaultStatusStrings,
      showsReasoning: showsReasoning,
      markdownStyle: markdownStyle,
      onToolApprovalResponse: onToolApprovalResponse
    )
  }

  public var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if shouldShowLoadMoreSentinel {
            Color.clear
              .frame(height: 1)
              .id(conversationTopSentinelID)
              .onAppear {
                loadOlderMessages(with: proxy)
              }
          }

          ForEach(Array(visibleMessages)) { message in
            messageView(message)
              .id(message.id)
          }

          Color.clear
            .frame(height: bottomInset)
            .animation(bottomInsetAnimation, value: bottomInset)
            .id(conversationBottomSentinelID)
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
        .scrollTargetLayout()
      }
      .scrollPosition(id: $scrollPosition, anchor: .bottom)
      .assistantMessageToolRenderers(toolRenderers)
      .assistantMessageToolStatusStrings(toolStatusStrings)
      .assistantMessageShowsReasoning(showsReasoning)
      .assistantMessageOnToolApprovalResponse { approvalID, approved, reason in
        onToolApprovalResponse?(approvalID, approved, reason)
      }
      .modifier(ScrollEdgeEffectCompat())
      .defaultScrollAnchor(.bottom)
      #if os(iOS)
      .modifier(ScrollDismissesKeyboardCompat())
      #endif
      .onAppear {
        syncVisibleCountWithMessages()
        scrollToBottom(proxy, animated: false)
        scrollPosition = conversationBottomSentinelID
        didPerformInitialScroll = true
      }
      .onChange(of: scrollPosition) {
        isAtBottom = scrollPosition == conversationBottomSentinelID
      }
      .onChange(of: messages.count) {
        syncVisibleCountWithMessages()
        guard didPerformInitialScroll else { return }
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
      .onChange(of: messages) {
        guard status == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: status) {
        let newStatus = status
        guard newStatus == .streaming else { return }
        guard isAtBottom else { return }
        requestStreamingScroll(proxy)
      }
      .onChange(of: bottomInset) {
        guard isAtBottom else { return }
        scrollToBottom(proxy, animated: true, animation: scrollAnimation)
      }
      .overlay(alignment: .bottom) {
        if showsScrollButton, isAtBottom == false {
          Button {
            scrollToBottom(proxy, animated: true, animation: scrollAnimation)
          } label: {
            Image(systemName: "arrow.down")
              .font(.system(size: 13, weight: .semibold))
              .frame(width: 32, height: 32)
              .glassEffect(.clear.interactive(), in: .circle)
              .contentShape(Circle())
              .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 0)
          }
          .buttonStyle(.plain)
          .padding(.bottom, 12)
          .accessibilityLabel("Scroll to latest")
          .transition(.opacity)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: isAtBottom)
    }
  }

  private var bottomInset: CGFloat {
    max(1, extraBottomPadding)
  }


  private var resolvedVisibleCount: Int {
    guard messages.isEmpty == false else { return 0 }
    let baseline = min(conversationMessagePageSize, messages.count)
    let desired = max(visibleCount, baseline)
    return min(desired, messages.count)
  }

  private var visibleMessages: ArraySlice<ChatMessage> {
    messages.suffix(resolvedVisibleCount)
  }

  private var shouldShowLoadMoreSentinel: Bool {
    resolvedVisibleCount < messages.count
  }

  private func syncVisibleCountWithMessages() {
    guard messages.isEmpty == false else {
      if visibleCount != 0 {
        visibleCount = 0
      }
      didPerformInitialScroll = false
      return
    }

    let baseline = min(conversationMessagePageSize, messages.count)
    if visibleCount < baseline {
      visibleCount = baseline
    } else if visibleCount > messages.count {
      visibleCount = messages.count
    }
  }

  private func loadOlderMessages(with proxy: ScrollViewProxy) {
    guard didPerformInitialScroll else { return }
    guard visibleCount < messages.count else { return }

    let currentFirstID = visibleMessages.first?.id
    let newCount = min(messages.count, visibleCount + conversationMessagePageSize)
    guard newCount != visibleCount else { return }

    visibleCount = newCount

    if let currentFirstID {
      DispatchQueue.main.async {
        proxy.scrollTo(currentFirstID, anchor: .top)
      }
    }
  }

  private func requestStreamingScroll(_ proxy: ScrollViewProxy) {
    guard pendingScrollTask == nil else { return }
    pendingScrollTask = Task { @MainActor in
      defer { pendingScrollTask = nil }
      try? await Task.sleep(nanoseconds: streamingScrollThrottleNanoseconds)
      guard isAtBottom else { return }
      scrollToBottom(proxy, animated: true, animation: streamingScrollAnimation)
    }
  }

  private func scrollToBottom(
    _ proxy: ScrollViewProxy,
    animated: Bool,
    animation: Animation = .easeOut(duration: 0.2)
  ) {
    let targetID: String
    if bottomInset > 0 {
      targetID = conversationBottomSentinelID
    } else if let lastID = messages.last?.id {
      targetID = lastID
    } else {
      targetID = conversationBottomSentinelID
    }

    if animated {
      withAnimation(animation) {
        scrollPosition = targetID
        proxy.scrollTo(targetID, anchor: .bottom)
      }
    } else {
      scrollPosition = targetID
      proxy.scrollTo(targetID, anchor: .bottom)
    }
  }

  @ViewBuilder
  private static func defaultMessageView(
    message: ChatMessage,
    toolStatusStrings: [String: ToolStatusStrings],
    toolDefaultStatusStrings: ToolStatusStrings,
    markdownStyle: AssistantMarkdownStyle
  ) -> some View {
    switch message.role {
    case .user:
      HStack(alignment: .top) {
        Spacer(minLength: 24)
        VStack(alignment: .trailing, spacing: 8) {
          if userAttachments(message).isEmpty == false {
            FileAttachmentPreviewRow(attachments: userAttachments(message), alignment: .trailing)
          }
          if userText(message).isEmpty == false {
            UserBubble(text: userText(message))
          }
        }
      }

    case .assistant:
      HStack(alignment: .top) {
        AssistantMessage(
          messageID: message.id,
          parts: message.parts,
          toolStatusStrings: toolStatusStrings,
          toolDefaultStatusStrings: toolDefaultStatusStrings,
          markdownStyle: markdownStyle
        )
      }

    case .system:
      Text(messageText(message))
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .tool:
      Text("Tool role message")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

    @unknown default:
      Text("Unsupported role: \(message.role.rawValue)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private static func messageText(_ message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private static func userText(_ message: ChatMessage) -> String {
    message.parts.compactMap { part in
      guard case let .text(text) = part else { return nil }
      return text.text
    }.joined()
  }

  private static func userAttachments(_ message: ChatMessage) -> [ChatFilePart] {
    message.parts.compactMap { part in
      guard case let .file(file) = part else { return nil }
      return file
    }
  }
}

private struct ScrollEdgeEffectCompat: ViewModifier {
  func body(content: Content) -> some View {
    content.scrollEdgeEffectStyle(.soft, for: .bottom)
  }
}


#if os(iOS)
private struct ScrollDismissesKeyboardCompat: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 16.0, *) {
      content.scrollDismissesKeyboard(.interactively)
    } else {
      content
    }
  }
}
#endif

public struct ConversationContent<Content: View>: View {
  public var spacing: CGFloat
  public var padding: EdgeInsets
  @ViewBuilder public var content: () -> Content

  public init(
    spacing: CGFloat = 32,
    padding: EdgeInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16),
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.spacing = spacing
    self.padding = padding
    self.content = content
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      content()
    }
    .padding(padding)
  }
}

public struct ConversationEmptyState<Content: View>: View {
  public var title: String
  public var description: String?
  public var icon: AnyView?
  @ViewBuilder public var content: () -> Content

  public init(
    title: String = "No messages yet",
    description: String? = "Start a conversation to see messages here",
    icon: AnyView? = nil,
    @ViewBuilder content: @escaping () -> Content = { EmptyView() }
  ) {
    self.title = title
    self.description = description
    self.icon = icon
    self.content = content
  }

  public var body: some View {
    VStack(spacing: 12) {
      if let icon {
        icon
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 4) {
        Text(title)
          .font(.subheadline.weight(.medium))

        if let description {
          Text(description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
      }

      content()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .padding(32)
    .multilineTextAlignment(.center)
  }
}

// ConversationScrollButton is currently handled inside Conversation, mirroring ../Assistant behavior.
